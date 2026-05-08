# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.ServerTest do
  use ExUnit.Case, async: true
  import Ultravisor.Protocol.Server

  @subject Ultravisor.Protocol.Server

  describe "decode/1" do
    test "decodes authentication ok" do
      data = <<?R, 8::32, 0::32>>
      assert [%@subject.Pkt{tag: :authentication, payload: :authentication_ok}] = decode(data)
    end

    test "decodes ready for query" do
      data = <<?Z, 5::32, ?I>>
      assert [%@subject.Pkt{tag: :ready_for_query, payload: :idle}] = decode(data)

      data = <<?Z, 5::32, ?T>>
      assert [%@subject.Pkt{tag: :ready_for_query, payload: :transaction}] = decode(data)
    end

    test "decodes backend key data" do
      data = <<?K, 12::32, 123::32, 456::32>>

      assert [%@subject.Pkt{tag: :backend_key_data, payload: %{pid: 123, key: 456}}] =
               decode(data)
    end

    test "decodes parameter status" do
      key = "server_version"
      val = "15.1"
      payload = key <> <<0>> <> val <> <<0>>
      len = byte_size(payload) + 4
      data = <<?S, len::32, payload::binary>>
      assert [%@subject.Pkt{tag: :parameter_status, payload: {^key, ^val}}] = decode(data)
    end

    test "decodes parameter description" do
      data = <<?t, 14::32, 2::16, 16::32, 23::32>>
      assert [%@subject.Pkt{tag: :parameter_description, payload: {2, [16, 23]}}] = decode(data)
    end

    test "decodes row description" do
      # field_name (string), table_oid (int32), attr_num (int16), data_type_oid (int32),
      # data_type_size (int16), type_modifier (int32), format_code (int16)
      field1 = "id" <> <<0>> <> <<1::32, 1::16, 23::32, 4::16, -1::32, 0::16>>
      data = <<?T, byte_size(field1) + 6::32, 1::16, field1::binary>>
      assert [%@subject.Pkt{tag: :row_description, payload: [field]}] = decode(data)
      assert field.name == "id"
      assert field.type_info == 23
    end

    test "decodes error response" do
      payload = "SFATAL" <> <<0>> <> "C28P01" <> <<0>> <> "Mmessage" <> <<0>> <> <<0>>
      data = <<?E, byte_size(payload) + 4::32, payload::binary>>
      assert [%@subject.Pkt{tag: :error_response, payload: fields}] = decode(data)
      assert "SFATAL" in fields
      assert "C28P01" in fields
    end
  end

  describe "decode_startup_packet/1" do
    test "decodes valid startup packet" do
      payload =
        "user" <> <<0>> <> "postgres" <> <<0>> <> "database" <> <<0>> <> "test_db" <> <<0>>

      len = byte_size(payload) + 8
      data = <<len::32, 196_608::32, payload::binary>>

      assert {:ok, %{tag: :startup, payload: %{"user" => "postgres", "database" => "test_db"}}} =
               @subject.decode_startup_packet(data)
    end

    test "returns error for missing user" do
      payload = "database" <> <<0>> <> "test_db" <> <<0>>
      len = byte_size(payload) + 8
      data = <<len::32, 196_608::32, payload::binary>>
      assert {:error, :bad_startup_payload} == @subject.decode_startup_packet(data)
    end

    test "returns error for malformed payload (odd fields)" do
      payload = "user" <> <<0>>
      len = byte_size(payload) + 8
      data = <<len::32, 196_608::32, payload::binary>>
      assert {:error, :bad_startup_payload} == @subject.decode_startup_packet(data)
    end
  end

  describe "error_message/2" do
    test "encodes error message correctly" do
      msg = @subject.error_message("28P01", "invalid password")
      decoded = @subject.decode(IO.iodata_to_binary(msg))
      assert [%@subject.Pkt{tag: :error_response, payload: fields}] = decoded
      assert "C28P01" in fields
      assert "Minvalid password" in fields
    end
  end

  describe "has_read_only_error?/1" do
    test "returns true for read only error" do
      pkts = [%{tag: :error_response, payload: ["SERROR", "VERROR", "C25006", "Mmessage"]}]
      assert @subject.has_read_only_error?(pkts)
    end

    test "returns false for other errors" do
      pkts = [%{tag: :error_response, payload: ["SERROR", "VERROR", "CXXXXX", "Mmessage"]}]
      refute @subject.has_read_only_error?(pkts)
    end
  end
end
