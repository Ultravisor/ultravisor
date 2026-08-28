# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.BackendStream do
  @moduledoc false

  defstruct buffer: <<>>, actions: :queue.new()

  def new, do: %__MODULE__{}

  def enqueue(%__MODULE__{actions: actions} = state, actions_to_add) do
    %{state | actions: Enum.reduce(actions_to_add, actions, &:queue.in/2)}
  end

  def process(%__MODULE__{buffer: buffer} = state, data) do
    process_packets(%{state | buffer: buffer <> data}, [])
  end

  defp process_packets(%__MODULE__{buffer: buffer} = state, output) when byte_size(buffer) < 5,
    do: {state, IO.iodata_to_binary(Enum.reverse(output))}

  defp process_packets(%__MODULE__{buffer: <<tag, length::32, rest::binary>>} = state, output) do
    payload_length = length - 4

    if byte_size(rest) < payload_length do
      {state, IO.iodata_to_binary(Enum.reverse(output))}
    else
      <<payload::binary-size(^payload_length), tail::binary>> = rest
      {actions, injected} = inject(state.actions, [])
      packet = <<tag, length::32, payload::binary>>
      {actions, forward?} = consume(actions, tag)
      state = %{state | actions: actions, buffer: tail}
      output = if forward?, do: [packet, injected | output], else: [injected | output]
      process_packets(state, output)
    end
  end

  defp inject(actions, output) do
    case :queue.out(actions) do
      {{:value, :inject_parse}, actions} -> inject(actions, [<<?1, 4::32>> | output])
      _ -> {actions, output}
    end
  end

  defp consume(actions, ?1), do: consume_action(actions, :intercept_parse)
  defp consume(actions, ?3), do: consume_action(actions, :intercept_close)
  defp consume(actions, _), do: {actions, true}

  defp consume_action(actions, action) do
    case :queue.out(actions) do
      {{:value, ^action}, actions} -> {actions, false}
      _ -> {actions, true}
    end
  end
end
