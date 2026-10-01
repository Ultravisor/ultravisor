# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.SockTest do
  use ExUnit.Case, async: false

  @subject Ultravisor.Sock

  doctest @subject

  test "sends data through a TCP socket" do
    {client, server} = tcp_pair()

    assert :ok = @subject.send({:gen_tcp, client}, "message")
    assert {:ok, "message"} = :gen_tcp.recv(server, 0, 1_000)
  end

  test "sets options through a TCP socket" do
    {client, _server} = tcp_pair(active: true)

    assert :ok = @subject.setopts({:gen_tcp, client}, active: false)
    assert {:ok, [active: false]} = :inet.getopts(client, [:active])
  end

  test "closes nil and TCP sockets" do
    assert :ok = @subject.close(nil)
    assert :ok = @subject.close({:gen_tcp, nil})

    {client, server} = tcp_pair()
    assert :ok = @subject.close({:gen_tcp, client})
    assert {:error, :closed} = :gen_tcp.recv(server, 0, 1_000)
  end

  test "gets the peer address from a TCP socket" do
    {client, _server} = tcp_pair()

    assert {:ok, {127, 0, 0, 1}} = @subject.addr({:gen_tcp, client})
  end

  test "sends data through an SSL socket" do
    {client, server} = ssl_pair()

    assert :ok = @subject.send({:ssl, client}, "message")
    assert {:ok, "message"} = :ssl.recv(server, 0, 1_000)
  end

  test "sets options through an SSL socket" do
    {client, _server} = ssl_pair()

    assert :ok = @subject.setopts({:ssl, client}, active: false)
    assert {:ok, [active: false]} = :ssl.getopts(client, [:active])
  end

  test "closes an SSL socket" do
    {client, server} = ssl_pair()

    assert :ok = @subject.close({:ssl, client})
    assert {:error, :closed} = :ssl.recv(server, 0, 1_000)
  end

  test "sends a PostgreSQL error through a TCP socket" do
    {client, server} = tcp_pair()

    assert :ok = @subject.send_error({:gen_tcp, client}, "XX000", "bad")

    assert {:ok, <<?E, length::32, payload::binary>>} = :gen_tcp.recv(server, 0, 1_000)
    assert length == byte_size(payload) + 4
    assert payload == <<?S, "FATAL", 0, ?V, "FATAL", 0, ?C, "XX000", 0, ?M, "bad", 0, 0>>
  end

  test "gets SNI and peer address from an SSL socket" do
    {client, server} = ssl_pair()

    assert "sock.example" = @subject.try_get_sni({:ssl, server})
    assert {:ok, {127, 0, 0, 1}} = @subject.addr({:ssl, client})
  end

  test "returns nil for SNI on a TCP socket" do
    {client, _server} = tcp_pair()

    assert is_nil(@subject.try_get_sni({:gen_tcp, client}))
  end

  test "returns an error for a closed TCP socket address" do
    {client, _server} = tcp_pair()
    :ok = :gen_tcp.close(client)

    assert :error = @subject.addr({:gen_tcp, client})
  end

  test "returns an error for a local TCP peer address" do
    path = Path.join(System.tmp_dir!(), "ultravisor-#{System.unique_integer()}.sock")

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, {:ifaddr, {:local, String.to_charlist(path)}}, active: false])

    parent = self()

    spawn_link(fn ->
      {:ok, server} = :gen_tcp.accept(listener)
      :ok = :gen_tcp.controlling_process(server, parent)
      send(parent, {:local_tcp_server, server})
    end)

    {:ok, client} =
      :gen_tcp.connect({:local, String.to_charlist(path)}, 0, [:binary, active: false])

    assert_receive {:local_tcp_server, server}
    :ok = :gen_tcp.close(listener)

    assert :error = @subject.addr({:gen_tcp, client})

    :ok = :gen_tcp.close(client)
    :ok = :gen_tcp.close(server)
    File.rm(path)
  end

  test "returns nil SNI and an error address for a closed SSL socket" do
    {client, _server} = ssl_pair()
    :ok = :ssl.close(client)

    assert is_nil(@subject.try_get_sni({:ssl, client}))
    assert :error = @subject.addr({:ssl, client})
  end

  defp ssl_pair do
    :ok = :ssl.start()
    certfile = Path.expand("../fixtures/example.cert.pem", __DIR__)
    keyfile = Path.expand("../fixtures/example.cert_key.pem", __DIR__)

    {:ok, listener} =
      :ssl.listen(0, [
        :binary,
        active: false,
        reuseaddr: true,
        certfile: String.to_charlist(certfile),
        keyfile: String.to_charlist(keyfile)
      ])

    {:ok, {_addr, port}} = :ssl.sockname(listener)
    parent = self()

    spawn_link(fn ->
      {:ok, tcp_socket} = :ssl.transport_accept(listener)
      {:ok, server} = :ssl.handshake(tcp_socket)
      :ok = :ssl.controlling_process(server, parent)
      send(parent, {:ssl_server, server})
    end)

    {:ok, client} =
      :ssl.connect(~c"localhost", port, [
        :binary,
        active: false,
        verify: :verify_none,
        server_name_indication: ~c"sock.example"
      ])

    assert_receive {:ssl_server, server}
    :ok = :ssl.close(listener)

    {client, server}
  end

  defp tcp_pair(client_opts \\ [active: false]) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_addr, port}} = :inet.sockname(listener)
    parent = self()

    spawn_link(fn ->
      {:ok, server} = :gen_tcp.accept(listener)
      :ok = :gen_tcp.controlling_process(server, parent)
      send(parent, {:tcp_server, server})
    end)

    {:ok, client} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary | client_opts])
    assert_receive {:tcp_server, server}
    :ok = :gen_tcp.close(listener)

    {client, server}
  end
end
