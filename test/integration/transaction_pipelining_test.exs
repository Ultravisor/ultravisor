# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Integration.TransactionPipeliningTest do
  use Ultravisor.DataCase, async: false

  alias Ultravisor.Protocol.Server

  @tenant "proxy_tenant1"

  @tag :integration
  test "delivers every reply before it releases a pipelined transaction backend" do
    sock = connect(@tenant)
    on_exit(fn -> :gen_tcp.close(sock) end)

    :ok = :gen_tcp.send(sock, pipeline(5))
    assert receive_ready_for_queries(sock, 5) == 5

    # The backend must be usable after the complete prior batch is delivered.
    :ok = :gen_tcp.send(sock, :pgo_protocol.encode_query_message("SELECT 1"))
    assert receive_ready_for_queries(sock, 1) == 1
  end

  @tag :integration
  test "reuses a named extended-protocol statement after transaction checkin" do
    sock = connect(@tenant)
    on_exit(fn -> :gen_tcp.close(sock) end)

    parse = packet(?P, "statement" <> <<0>> <> "SELECT $1::int" <> <<0, 0::16>>)
    bind = packet(?B, <<0, "statement", 0, 0::16, 1::16, 1::32, ?1, 0::16>>)
    execute = packet(?E, <<0, 0::32>>)
    sync = <<?S, 4::32>>

    :ok = :gen_tcp.send(sock, [parse, bind, execute, sync])
    assert [?1, ?2, ?D, ?C, ?Z] = receive_response(sock)
    holder = connect(@tenant)
    on_exit(fn -> :gen_tcp.close(holder) end)
    :ok = :gen_tcp.send(holder, :pgo_protocol.encode_query_message("BEGIN"))
    assert receive_ready_for_queries(holder, 1) == 1

    :ok = :gen_tcp.send(sock, [bind, execute, sync])
    assert [?2, ?D, ?C, ?Z] = receive_response(sock)

    :ok = :gen_tcp.send(holder, :pgo_protocol.encode_query_message("COMMIT"))
    assert receive_ready_for_queries(holder, 1) == 1
  end

  defp connect(tenant) do
    db_conf = Application.fetch_env!(:ultravisor, Ultravisor.Repo)
    port = Application.fetch_env!(:ultravisor, :proxy_port_transaction)
    {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])

    authenticate(sock, "#{db_conf[:username]}.#{tenant}", db_conf[:password], db_conf[:database])
    sock
  end

  defp authenticate(sock, user, password, database) do
    :ok =
      :gen_tcp.send(
        sock,
        :pgo_protocol.encode_startup_message([{"user", user}, {"database", database}])
      )

    {:ok, <<?R, _::32, 10::32, _::binary>>} = :gen_tcp.recv(sock, 0, 5_000)

    nonce = :pgo_scram.get_nonce(16)
    client_first = :pgo_scram.get_client_first(user, nonce)
    initial = ["SCRAM-SHA-256", 0, <<:erlang.iolist_size(client_first)::32>>, client_first]

    :ok = :gen_tcp.send(sock, :pgo_protocol.encode_scram_response_message(initial))
    {:ok, <<?R, _::32, 11::32, server_first::binary>>} = :gen_tcp.recv(sock, 0, 5_000)

    server_first_parts = :pgo_scram.parse_server_first(server_first, nonce)

    {client_final, _server_proof} =
      :pgo_scram.get_client_final(server_first_parts, nonce, user, password)

    :ok = :gen_tcp.send(sock, :pgo_protocol.encode_scram_response_message(client_final))
    {:ok, response} = :gen_tcp.recv(sock, 0, 5_000)
    assert receive_ready_for_queries(sock, 1, response) == 1
  end

  defp pipeline(count) do
    Enum.map(1..count, fn number ->
      :pgo_protocol.encode_query_message("SELECT #{number}")
    end)
  end

  defp packet(tag, payload), do: <<tag, byte_size(payload) + 4::32, payload::binary>>

  defp receive_response(sock, buffer \\ <<>>) do
    {packets, rest} = split_packets(buffer)

    if Enum.any?(packets, &match?(<<?Z, _::binary>>, &1)) do
      tags = Enum.map(packets, &binary_part(&1, 0, 1))
      refute ?E in tags
      Enum.map(tags, fn <<tag, _::binary>> -> tag end)
    else
      {:ok, data} = :gen_tcp.recv(sock, 0, 5_000)
      receive_response(sock, rest <> data)
    end
  end

  defp split_packets(data, packets \\ [])
  defp split_packets(<<>>, packets), do: {Enum.reverse(packets), <<>>}
  defp split_packets(data, packets) when byte_size(data) < 5, do: {Enum.reverse(packets), data}

  defp split_packets(<<_tag, length::32, rest::binary>> = data, packets) do
    payload_length = length - 4

    if byte_size(rest) < payload_length do
      {Enum.reverse(packets), data}
    else
      <<payload::binary-size(^payload_length), tail::binary>> = rest
      split_packets(tail, [<<binary_part(data, 0, 5)::binary, payload::binary>> | packets])
    end
  end

  defp receive_ready_for_queries(sock, expected, buffer \\ <<>>, received \\ 0) do
    {:ok, statuses, _, rest} = Server.backend_ready_for_query_statuses(buffer)
    received = received + statuses

    if received >= expected do
      received
    else
      case :gen_tcp.recv(sock, 0, 5_000) do
        {:ok, data} ->
          receive_ready_for_queries(sock, expected, rest <> data, received)

        {:error, reason} ->
          flunk("received #{received}/#{expected} ReadyForQuery messages: #{inspect(reason)}")
      end
    end
  end
end
