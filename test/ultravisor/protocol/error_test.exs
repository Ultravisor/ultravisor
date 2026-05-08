# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.ErrorTest do
  use ExUnit.Case, async: true
  @subject Ultravisor.Protocol.Error

  defmodule TestException do
    defexception [:message, pg_code: "T001", pg_severity: :error]
  end

  defmodule GenericException do
    defexception [:message]
  end

  describe "encode/2" do
    test "encodes custom exception" do
      exc = %TestException{message: "test message"}
      encoded = @subject.encode(exc)
      # Encoded message is iodata, convert to binary to check
      bin = IO.iodata_to_binary(encoded)

      # Should be an ErrorResponse packet (?E)
      assert <<?E, _len::32, payload::binary>> = bin
      # Check for fields
      assert "SERROR" <> <<0>> <> "VERROR" <> <<0>> <> "CT001" <> <<0>> <> _ = payload

      assert "MUltravisor.Protocol.ErrorTest.TestException: test message" in String.split(
               payload,
               <<0>>
             )
    end

    test "encodes generic exception with default values" do
      exc = %GenericException{message: "generic message"}
      encoded = @subject.encode(exc)
      bin = IO.iodata_to_binary(encoded)

      assert <<?E, _len::32, payload::binary>> = bin
      assert "SFATAL" <> <<0>> <> "VFATAL" <> <<0>> <> "CUV000" <> <<0>> <> _ = payload
    end

    test "includes location from stacktrace" do
      exc = %TestException{message: "loc test"}
      stack = [{Ultravisor.SomeModule, :some_func, 2, [file: "lib/some_file.ex", line: 42]}]
      encoded = @subject.encode(exc, stack)
      bin = IO.iodata_to_binary(encoded)

      assert bin =~ "lib/some_file.ex"
      assert bin =~ "42"
      assert bin =~ "Ultravisor.SomeModule.some_func/2"
    end
  end
end
