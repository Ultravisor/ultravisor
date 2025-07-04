# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.ProtocolTest do
  use ExUnit.Case, async: true

  @subject Ultravisor.Protocol.Server

  require Ultravisor.Protocol.Server

  @initial_data %{
    "DateStyle" => "ISO, MDY",
    "IntervalStyle" => "postgres",
    "TimeZone" => "UTC",
    "application_name" => "ultravisor",
    "client_encoding" => "UTF8",
    "default_transaction_read_only" => "off",
    "in_hot_standby" => "off",
    "integer_datetimes" => "on",
    "is_superuser" => "on",
    "server_encoding" => "UTF8",
    "server_version" => "14.6 (Debian 14.6-1.pgdg110+1)",
    "session_authorization" => "postgres",
    "standard_conforming_strings" => "on"
  }

  @auth_bin_error <<69, 0, 0, 0, 111, 83, 70, 65, 84, 65, 76, 0, 86, 70, 65, 84, 65, 76, 0, 67,
                    50, 56, 80, 48, 49, 0, 77, 112, 97, 115, 115, 119, 111, 114, 100, 32, 97, 117,
                    116, 104, 101, 110, 116, 105, 99, 97, 116, 105, 111, 110, 32, 102, 97, 105,
                    108, 101, 100, 32, 102, 111, 114, 32, 117, 115, 101, 114, 32, 34, 116, 101,
                    115, 116, 95, 119, 114, 111, 110, 103, 95, 117, 115, 101, 114, 34, 0, 70, 97,
                    117, 116, 104, 46, 99, 0, 76, 51, 51, 53, 0, 82, 97, 117, 116, 104, 95, 102,
                    97, 105, 108, 101, 100, 0, 0>>

  test "encode_parameter_status/1" do
    result = @subject.encode_parameter_status(@initial_data)

    for entry <- @initial_data do
      assert {key, value} = entry
      assert is_binary(key)
      assert is_binary(value)
      encoded = @subject.encode_pkt(:parameter_status, key, value)
      assert encoded in result
    end
  end

  test "encode_pkt/3" do
    key = "TimeZone"
    value = "UTC"
    result = @subject.encode_pkt(:parameter_status, key, value)

    assert result == [<<?S, 17::32>>, [key, <<0>>, value, <<0>>]]
  end

  test "backend_key_data/0" do
    {header, payload} = @subject.backend_key_data()
    len = byte_size(payload) + 4

    assert [
             %@subject.Pkt{
               tag: :backend_key_data,
               len: 13,
               payload: %{pid: _, key: _}
             }
           ] = @subject.decode([header, payload] |> IO.iodata_to_binary())

    assert header == <<?K, len::32>>
    assert byte_size(payload) == 8
  end

  test "decode_payload for error_response" do
    assert @subject.decode(@auth_bin_error) == [
             %Ultravisor.Protocol.Server.Pkt{
               tag: :error_response,
               len: 112,
               payload: [
                 "SFATAL",
                 "VFATAL",
                 "C28P01",
                 "Mpassword authentication failed for user \"test_wrong_user\"",
                 "Fauth.c",
                 "L335",
                 "Rauth_failed"
               ]
             }
           ]
  end

  test "cancel_message/2" do
    pid = 123
    key = 123_456
    expected = <<0, 0, 0, 16, 4, 210, 22, 46, 0, 0, 0, 123, 0, 1, 226, 64>>

    assert @subject.cancel_message(pid, key) == expected
  end
end
