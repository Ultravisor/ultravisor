# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.BackendStreamTest do
  use ExUnit.Case, async: true

  @subject Ultravisor.Protocol.BackendStream

  test "clears queued actions after ErrorResponse" do
    error = packet(?E, <<>>)
    ready = packet(?Z, "I")

    state = @subject.new() |> @subject.enqueue([:intercept_close, :inject_parse])
    {state, forwarded, settled} = @subject.process(state, error <> ready)
    assert forwarded == error <> ready
    assert settled == 1
    assert :queue.is_empty(state.actions)

    parse_complete = packet(?1, <<>>)
    {_state, forwarded, settled} = @subject.process(state, parse_complete)

    assert forwarded == parse_complete
    assert settled == 0
  end

  test "flushes every pending ParseComplete before ReadyForQuery" do
    ready = packet(?Z, "I")
    state = @subject.new() |> @subject.enqueue([:inject_parse, :inject_parse])

    {state, forwarded, settled} = @subject.process(state, ready)

    assert forwarded == packet(?1, <<>>) <> packet(?1, <<>>) <> ready
    assert settled == 2
    assert :queue.is_empty(state.actions)
  end

  defp packet(tag, payload), do: <<tag, byte_size(payload) + 4::32, payload::binary>>
end
