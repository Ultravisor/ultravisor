# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.PreparedStatements do
  @moduledoc """
  Client-owned named prepared statement state.

  Each Parse gets a client-scoped backend name. This prevents prepared plans
  from different clients from colliding when a backend connection is reused.
  """

  @type statement() :: %{backend_name: binary(), parse_packet: binary()}
  @type t() ::
          %__MODULE__{
            buffer: binary(),
            client_id: binary(),
            parse_count: non_neg_integer(),
            statements: %{binary() => statement()}
          }

  @type packet() ::
          {:parse, binary(), binary()}
          | {:close, binary(), binary()}
          | {:bind, binary(), binary(), binary()}

  defstruct buffer: <<>>, client_id: <<>>, parse_count: 0, statements: %{}

  @spec new() :: t()
  def new, do: %__MODULE__{client_id: :crypto.strong_rand_bytes(16)}

  @spec process(t(), binary()) ::
          {:ok, t(), [binary()], [packet()], non_neg_integer()}
          | {:error, {:unknown_statement, binary()}}
  def process(%__MODULE__{buffer: <<>>} = state, data), do: decode(data, state)

  def process(%__MODULE__{buffer: buffer} = state, data), do: decode(buffer <> data, state)

  defp decode(data, state) do
    case process_packets(data, state, [], []) do
      {:ok, state, packets, operations} ->
        {:ok, state, packets, operations, Enum.count(packets, &ready_for_query?/1)}

      {:error, _} = error ->
        error
    end
  end

  defp ready_for_query?(<<?Q, _::binary>>), do: true
  defp ready_for_query?(<<?S, _::binary>>), do: true
  defp ready_for_query?(_), do: false

  defp process_packets(<<>>, state, packets, operations),
    do: {:ok, %{state | buffer: <<>>}, Enum.reverse(packets), Enum.reverse(operations)}

  defp process_packets(data, state, packets, operations) when byte_size(data) < 5,
    do: {:ok, %{state | buffer: data}, Enum.reverse(packets), Enum.reverse(operations)}

  defp process_packets(<<_tag, length::32, _::binary>>, _state, _packets, _operations)
       when length < 4,
       do: {:error, {:invalid_packet_length, length}}

  defp process_packets(<<tag, length::32, rest::binary>> = data, state, packets, operations) do
    payload_length = length - 4

    if byte_size(rest) < payload_length do
      {:ok, %{state | buffer: data}, Enum.reverse(packets), Enum.reverse(operations)}
    else
      <<payload::binary-size(^payload_length), tail::binary>> = rest

      with {:ok, state, packet, operation} <- process_packet(tag, length, payload, state) do
        process_packets(tail, state, [packet | packets], prepend_operation(operation, operations))
      end
    end
  end

  defp prepend_operation(nil, operations), do: operations
  defp prepend_operation(operation, operations), do: [operation | operations]

  defp process_packet(?P, length, payload, %__MODULE__{parse_count: count} = state) do
    {client_name, parse_data} = take_name(payload)

    if client_name == <<>> do
      {:ok, state, packet(?P, length, payload), nil}
    else
      count = count + 1
      backend_name = backend_name(state.client_id, count, parse_data)

      packet =
        <<?P, length + byte_size(backend_name) - byte_size(client_name)::32, backend_name::binary,
          0, parse_data::binary>>

      statement = %{backend_name: backend_name, parse_packet: packet}

      state = %{
        state
        | parse_count: count,
          statements: Map.put(state.statements, client_name, statement)
      }

      {:ok, state, packet, {:parse, backend_name, packet}}
    end
  end

  defp process_packet(?B, length, payload, state) do
    {portal, statement_data} = take_name(payload)
    {client_name, bind_data} = take_name(statement_data)

    if client_name == <<>> do
      {:ok, state, packet(?B, length, payload), nil}
    else
      case Map.fetch(state.statements, client_name) do
        {:ok, %{backend_name: backend_name, parse_packet: parse_packet}} ->
          packet =
            <<?B, length + byte_size(backend_name) - byte_size(client_name)::32, portal::binary,
              0, backend_name::binary, 0, bind_data::binary>>

          {:ok, state, packet, {:bind, backend_name, packet, parse_packet}}

        :error ->
          {:error, {:unknown_statement, client_name}}
      end
    end
  end

  defp process_packet(?D, length, <<?S, rest::binary>>, state) do
    {client_name, describe_data} = take_name(rest)

    case Map.fetch(state.statements, client_name) do
      {:ok, %{backend_name: backend_name}} ->
        packet =
          <<?D, length + byte_size(backend_name) - byte_size(client_name)::32, ?S,
            backend_name::binary, 0, describe_data::binary>>

        {:ok, state, packet, nil}

      :error ->
        {:ok, state, packet(?D, length, <<?S, rest::binary>>), nil}
    end
  end

  defp process_packet(?C, length, <<?S, rest::binary>>, state) do
    {client_name, _} = take_name(rest)

    case Map.pop(state.statements, client_name) do
      {nil, statements} ->
        {:ok, %{state | statements: statements}, packet(?C, length, <<?S, rest::binary>>), nil}

      {%{backend_name: backend_name}, statements} ->
        packet =
          <<?C, length + byte_size(backend_name) - byte_size(client_name)::32, ?S,
            backend_name::binary, 0>>

        {:ok, %{state | statements: statements}, packet, {:close, backend_name, packet}}
    end
  end

  defp process_packet(tag, length, payload, state),
    do: {:ok, state, packet(tag, length, payload), nil}

  defp take_name(data) do
    case :binary.split(data, <<0>>) do
      [name, rest] -> {name, rest}
      [name] -> {name, <<>>}
    end
  end

  defp backend_name(client_id, count, parse_data) do
    digest =
      :crypto.hash(:sha256, [client_id, <<count::64>>, parse_data])
      |> Base.url_encode64(padding: false)

    "uv_" <> digest
  end

  defp packet(tag, length, payload), do: <<tag, length::32, payload::binary>>
end
