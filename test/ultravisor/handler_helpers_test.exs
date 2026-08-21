# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.HandlerHelpersTest do
  use ExUnit.Case, async: true

  @subject Ultravisor.HandlerHelpers

  doctest @subject

  describe "parse_user_info/1" do
    test "extracts the external_id from the username" do
      payload = %{"user" => "test.user.external_id"}
      {name, external_id, nil} = @subject.parse_user_info(payload)
      assert name == "test.user"
      assert external_id == "external_id"
    end

    test "username consists only of username" do
      username = "username"
      payload = %{"user" => username}
      {user, nil, nil} = @subject.parse_user_info(payload)
      assert username == user
    end

    test "external_id in options" do
      user = "test.user"
      external_id = "external_id"
      payload = %{"options" => %{"reference" => external_id}, "user" => user}
      {user1, external_id1, nil} = @subject.parse_user_info(payload)
      assert user1 == user
      assert external_id1 == external_id
    end

    test "unicode in username" do
      payload = %{"user" => "тестовe.імʼя.external_id"}
      {name, external_id, nil} = @subject.parse_user_info(payload)
      assert name == "тестовe.імʼя"
      assert external_id == "external_id"
    end

    test "extracts db_name" do
      payload = %{"user" => "user", "database" => "postgres_test"}
      {name, nil, db_name} = @subject.parse_user_info(payload)
      assert name == "user"
      assert db_name == "postgres_test"
    end
  end

  describe "socket helpers" do
    test "sends data through a TCP socket" do
      {client, server} = tcp_pair()

      assert :ok = @subject.sock_send({:gen_tcp, client}, "message")
      assert {:ok, "message"} = :gen_tcp.recv(server, 0, 1_000)
    end

    test "sets options through a TCP socket" do
      {client, _server} = tcp_pair(active: true)

      assert :ok = @subject.setopts({:gen_tcp, client}, active: false)
      assert {:ok, [active: false]} = :inet.getopts(client, [:active])
    end

    test "closes nil and TCP sockets" do
      assert :ok = @subject.sock_close(nil)
      assert :ok = @subject.sock_close({:gen_tcp, nil})

      {client, server} = tcp_pair()
      assert :ok = @subject.sock_close({:gen_tcp, client})
      assert {:error, :closed} = :gen_tcp.recv(server, 0, 1_000)
    end

    test "keeps a TCP socket when SSL is disabled" do
      {client, _server} = tcp_pair()

      assert {:ok, {:gen_tcp, ^client}} = @subject.try_ssl_handshake({:gen_tcp, client}, false)
    end

    test "keeps a TCP socket when the server rejects SSL" do
      {client, server} = tcp_pair()
      assert :ok = :gen_tcp.send(server, "N")

      assert {:ok, {:gen_tcp, ^client}} = @subject.ssl_recv({:gen_tcp, client})
    end

    test "gets the peer address from a TCP socket" do
      {client, _server} = tcp_pair()

      assert {:ok, {127, 0, 0, 1}} = @subject.addr_from_sock({:gen_tcp, client})
    end
  end

  describe "cancel query notifications" do
    test "broadcasts a cancel query notification" do
      request_id = System.unique_integer([:positive])
      assert :ok = @subject.listen_cancel_query(request_id, request_id)
      assert :ok = @subject.send_cancel_query(request_id, request_id)
      assert_receive :cancel_query
    end
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
