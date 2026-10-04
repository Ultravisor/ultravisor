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
    process_packets(%{state | buffer: buffer <> data}, [], 0)
  end

  defp process_packets(%__MODULE__{buffer: buffer} = state, output, settled_count)
       when byte_size(buffer) < 5,
       do: {state, IO.iodata_to_binary(Enum.reverse(output)), settled_count}

  defp process_packets(
         %__MODULE__{buffer: <<tag, length::32, rest::binary>>} = state,
         output,
         settled_count
       ) do
    payload_length = length - 4

    if byte_size(rest) < payload_length do
      {state, IO.iodata_to_binary(Enum.reverse(output)), settled_count}
    else
      <<payload::binary-size(^payload_length), tail::binary>> = rest
      packet = <<tag, length::32, payload::binary>>
      {actions, injected, settled} = backend_actions(state.actions, tag)
      {actions, forward?} = consume(actions, tag)
      state = %{state | actions: actions, buffer: tail}
      output = if forward?, do: [packet, injected | output], else: [injected | output]
      process_packets(state, output, settled_count + settled)
    end
  end

  defp backend_actions(actions, ?E) do
    settled = Enum.count(:queue.to_list(actions), &(&1 == :inject_parse))
    {:queue.new(), [], settled}
  end

  defp backend_actions(actions, ?Z), do: flush_injected(actions)

  defp backend_actions(actions, _tag), do: inject(actions, [], 0)

  defp flush_injected(actions) do
    count = Enum.count(:queue.to_list(actions), &(&1 == :inject_parse))
    injected = List.duplicate(<<?1, 4::32>>, count)
    {:queue.new(), injected, count}
  end

  defp inject(actions, output, count) do
    case :queue.out(actions) do
      {{:value, :inject_parse}, actions} ->
        inject(actions, [<<?1, 4::32>> | output], count + 1)

      _ ->
        {actions, output, count}
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
