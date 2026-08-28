# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.PreparedStatementsTest do
  use ExUnit.Case, async: true

  @subject Ultravisor.Protocol.PreparedStatements

  test "rewrites named Parse and Bind packets to a stable backend name" do
    parse = packet(?P, "client" <> <<0>> <> "select $1" <> <<0, 0::16>>)
    bind = packet(?B, <<0, "client", 0, 0::16, 0::16, 0::16>>)

    assert {:ok, state, [rewritten_parse, rewritten_bind],
            [
              {:parse, backend_name, rewritten_parse},
              {:bind, backend_name, rewritten_bind, rewritten_parse}
            ]} =
             @subject.new() |> @subject.process(parse <> bind)

    assert <<?P, _::32, ^backend_name::binary, 0, _::binary>> = rewritten_parse
    assert <<?B, _::32, 0, ^backend_name::binary, 0, _::binary>> = rewritten_bind
    assert state.statements["client"].backend_name == backend_name
  end

  test "retains an incomplete packet until its next TCP payload" do
    parse = packet(?P, "client" <> <<0>> <> "select 1" <> <<0, 0::16>>)
    <<prefix::binary-size(6), suffix::binary>> = parse

    assert {:ok, state, [], []} = @subject.new() |> @subject.process(prefix)

    assert {:ok, _state, [packet], [{:parse, _name, packet}]} =
             @subject.process(state, suffix)
  end

  test "rejects Bind for a statement not owned by the client" do
    bind = packet(?B, <<0, "missing", 0, 0::16, 0::16, 0::16>>)

    assert {:error, {:unknown_statement, "missing"}} =
             @subject.new() |> @subject.process(bind)
  end

  test "passes unnamed Parse and Bind messages through unchanged" do
    parse = packet(?P, <<0, "select $1", 0, 0::16>>)
    bind = packet(?B, <<0, 0, 0::16, 0::16, 0::16>>)

    assert {:ok, _state, [^parse, ^bind], []} =
             @subject.new() |> @subject.process(parse <> bind)
  end

  defp packet(tag, payload), do: <<tag, byte_size(payload) + 4::32, payload::binary>>
end
