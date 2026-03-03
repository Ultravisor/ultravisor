# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.ErrorTest do
  use ExUnit.Case, async: false

  @subject Ultravisor.Protocol.Error

  alias Ultravisor.Protocol.Errors
  alias Ultravisor.Protocol.Server

  doctest @subject

  describe "encode/2" do
    test "general exceptions are encoded as is" do
      msg = @subject.encode(%RuntimeError{})

      assert %{
               "C" => "UV000",
               "M" => "RuntimeError: runtime error",
               "S" => "FATAL",
               "V" => "FATAL"
             } == decode_error(msg)
    end

    test "internal errors have fixed code" do
      msg = @subject.encode(%Errors.SSLRequiredError{})

      assert %{
               "C" => "UV002",
               "M" => "SSLRequiredError: SSL connection is required",
               "S" => "FATAL",
               "V" => "FATAL"
             } == decode_error(msg)
    end

    test "location is set to Ultravisor location, not top of stacktrace" do
      {exception, stacktrace} =
        try do
          String.split(nil)
        rescue
          exception -> {exception, __STACKTRACE__}
        end

      msg = @subject.encode(exception, stacktrace)

      assert %{
               "F" => location,
               "L" => line
             } = decode_error(msg)

      assert String.ends_with?(__ENV__.file, location)
      assert {_, ""} = Integer.parse(line)
    end
  end

  defp decode_error(msg) do
    bin = IO.iodata_to_binary(msg)

    assert {:ok, %{tag: :error_response, payload: payload}, ""} = Server.decode_pkt(bin)

    for <<kind>> <> data <- payload, into: %{}, do: {<<kind>>, data}
  end
end
