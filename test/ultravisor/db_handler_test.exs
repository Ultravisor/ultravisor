# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.DbHandlerTest do
  use ExUnit.Case, async: true

  import Ultravisor, only: [conn_id: 1]
  import Ultravisor.DbHandler, only: [data: 1]

  alias Ultravisor.DbHandler, as: Db

  @id conn_id(tenant: "tenant", user: "user", db_name: "postgres")

  defp sockpair do
    {:ok, listen} = :gen_tcp.listen(0, mode: :binary, active: false)
    {:ok, {address, port}} = :inet.sockname(listen)
    this = self()
    ref = make_ref()

    spawn(fn ->
      {:ok, recv} = :gen_tcp.accept(listen)

      :gen_tcp.controlling_process(recv, this)

      send(this, {ref, recv})
    end)

    {:ok, send} = :gen_tcp.connect(address, port, mode: :binary, active: false)
    assert_receive {^ref, recv}

    {send, recv}
  end

  describe "init/1" do
    test "starts with correct state" do
      args = %{
        id: @id,
        auth: %{},
        tenant: {:single, "test_tenant"},
        user_alias: "test_user_alias",
        user: "user",
        mode: :transaction,
        replica_type: :single,
        log_level: nil,
        reconnect_retries: 5
      }

      {:ok, :connect, data, {_, next_event, _}} = Db.init(args)
      assert next_event == :internal

      assert data(
               sock: nil,
               caller: nil,
               sent: false,
               auth: auth,
               tenant: tenant,
               buffer: [],
               db_state: nil,
               parameter_status: parameter_status,
               nonce: nil,
               server_proof: nil
             ) = data

      assert auth == args.auth
      assert tenant == args.tenant
      assert parameter_status == %{}
    end
  end

  describe "handle_event/4" do
    test "db is available" do
      {:ok, sock} = :gen_tcp.listen(0, mode: :binary, active: false)
      {:ok, {host, port}} = :inet.sockname(sock)

      secrets = fn -> %{user: "some user", db_user: "some user"} end

      auth = %{
        host: host,
        port: port,
        user: "some user",
        require_user: true,
        database: "some database",
        application_name: "some application name",
        ip_version: :inet,
        secrets: secrets
      }

      state =
        Db.handle_event(
          :internal,
          nil,
          :connect,
          data(
            auth: auth,
            sock: {:gen_tcp, nil},
            id: @id,
            proxy: false
          )
        )

      assert {:next_state, :authentication,
              data(
                auth: %{
                  application_name: "some application name",
                  database: "some database",
                  host: ^host,
                  port: ^port,
                  user: "some user",
                  require_user: true,
                  ip_version: :inet,
                  secrets: ^secrets
                },
                sock: {:gen_tcp, _},
                id: @id,
                proxy: false
              )} = state
    end

    test "db is not available" do
      # We assume that there is nothing running on this port
      # credo:disable-for-next-line Credo.Check.Readability.LargeNumbers
      {host, port} = {{127, 0, 0, 1}, 12345}

      secrets = fn -> %{user: "some user", db_user: "some user"} end

      auth = %{
        id: @id,
        host: host,
        port: port,
        user: "some user",
        database: "some database",
        application_name: "some application name",
        require_user: true,
        ip_version: :inet,
        secrets: secrets
      }

      state =
        Db.handle_event(
          :internal,
          nil,
          :connect,
          data(
            auth: auth,
            sock: nil,
            id: @id,
            proxy: false,
            reconnect_retries: 5
          )
        )

      assert state == {:keep_state_and_data, {:state_timeout, 2_500, :connect}}
    end
  end

  describe "handle_event/4 info tcp authentication authentication_md5_password payload events" do
    test "keeps state while sending the digested md5" do
      # `82` is `?R`, which identifies the payload tag as `:authentication`
      # `0, 0, 0, 12` is the packet length
      # `0, 0, 0, 5` is the authentication type, identified as `:authentication_md5_password`
      # `100, 100, 100, 100` is the md5 salt from db, a random 4 bytes value
      bin = <<82, 0, 0, 0, 12, 0, 0, 0, 5, 100, 100, 100, 100>>

      {a, b} = sockpair()

      content = {:tcp, b, bin}

      data =
        data(
          auth: %{
            password: fn -> "some_password" end,
            user: "some_user",
            method: :password
          },
          sock: {:gen_tcp, a}
        )

      assert :keep_state_and_data = Db.handle_event(:info, content, :authentication, data)

      assert {:ok, message} = :gen_tcp.recv(b, 0)

      assert message == <<?p, 40::integer-32, "md5", "ae5546ff52734a18d0277977f626946c", 0>>
    end
  end

  describe "check_ready/1" do
    test "ready_for_query valid" do
      assert {:ready_for_query, :transaction_block} == Db.check_ready(<<90, 0, 0, 0, 5, ?T>>)

      assert {:ready_for_query, :transaction_block} ==
               Db.check_ready(<<1, 1, 1, 90, 0, 0, 0, 5, ?T>>)

      assert {:ready_for_query, :failed_transaction_block} ==
               Db.check_ready(<<90, 0, 0, 0, 5, ?E>>)

      assert {:ready_for_query, :failed_transaction_block} ==
               Db.check_ready(<<1, 1, 1, 90, 0, 0, 0, 5, ?E>>)

      assert {:ready_for_query, :idle} == Db.check_ready(<<90, 0, 0, 0, 5, ?I>>)

      assert {:ready_for_query, :idle} ==
               Db.check_ready(<<1, 1, 1, 90, 0, 0, 0, 5, ?I>>)
    end

    test "ready_for_query not valid" do
      assert :continue == Db.check_ready(<<>>)
      assert :continue == Db.check_ready(<<90, 0, 0, 0, 5, ?I, 1, 1, 1>>)
      assert :continue == Db.check_ready(<<1, 1, 1, 90, 0, 0, 0, 5, ?I, 1, 1, 1>>)
    end
  end
end
