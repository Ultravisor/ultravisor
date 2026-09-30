# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.WsProxyTest do
  use ExUnit.Case, async: true
  alias UltravisorWeb.WsProxy

  @password_pkt <<?p, 13::32, "postgres", 0>>

  defp sockpair do
    {:ok, listen} = :gen_tcp.listen(0, mode: :binary, active: false)
    {:ok, {address, port}} = :inet.sockname(listen)
    {:ok, client} = :gen_tcp.connect(address, port, mode: :binary, active: false)
    {:ok, server} = :gen_tcp.accept(listen)
    :ok = :gen_tcp.close(listen)
    {client, server}
  end

  test "filter the password packet" do
    bin = "hello"
    assert WsProxy.filter_pass_pkt(<<@password_pkt::binary, bin::binary>>) == bin
    assert WsProxy.filter_pass_pkt(bin) == bin
  end

  test "waits for a complete ReadyForQuery across TCP payloads" do
    {socket, peer} = sockpair()
    ready = <<?Z, 5::32, ?I>>
    <<prefix::binary-size(3), suffix::binary>> = ready
    state = %{WsProxy.init(nil) | socket: socket, acc: <<@password_pkt::binary, "frontend">>}

    assert {[{:binary, ^prefix}], %{status: :startup, backend_buffer: ^prefix} = state} =
             WsProxy.websocket_info({:tcp, :upstream, prefix}, state)

    assert {[{:binary, ^suffix}], %{status: :idle, backend_buffer: <<>>, acc: nil}} =
             WsProxy.websocket_info({:tcp, :upstream, suffix}, state)

    assert {:ok, "frontend"} = :gen_tcp.recv(peer, 0)
    :ok = :gen_tcp.close(socket)
    :ok = :gen_tcp.close(peer)
  end

  test "does not match a DataRow whose payload ends in ReadyForQuery bytes" do
    {socket, peer} = sockpair()
    collision = <<?D, 10::32, ?Z, 5::32, ?I>>
    state = %{WsProxy.init(nil) | socket: socket, acc: @password_pkt}

    assert {[{:binary, ^collision}], %{status: :startup, backend_buffer: <<>>}} =
             WsProxy.websocket_info({:tcp, :upstream, collision}, state)

    refute_receive {:tcp, _, _}
    :ok = :gen_tcp.close(socket)
    :ok = :gen_tcp.close(peer)
  end
end
