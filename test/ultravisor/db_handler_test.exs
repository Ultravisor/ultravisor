# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.DbHandlerTest do
  use ExUnit.Case, async: true
  use Repatch.ExUnit

  import Ultravisor, only: [conn_id: 1]
  import Ultravisor.DbHandler, only: [data: 1]

  alias Ultravisor.DbHandler, as: Db
  require Ultravisor.Protocol.Server, as: Server

  @id conn_id(tenant: "tenant", user: "user", db_name: "postgres")

  @tls_send_chunk_size 8_192

  defp patch_sock_send(result \\ :ok) do
    test_process = self()

    Repatch.patch(Ultravisor.HandlerHelpers, :sock_send, fn socket, payload ->
      send(test_process, {:sock_send, socket, IO.iodata_to_binary(payload)})
      result
    end)
  end

  defp receive_chunks(socket, count) do
    for _ <- 1..count do
      assert_receive {:sock_send, ^socket, payload}
      payload
    end
  end

  defp forwarding_data(client_sock) do
    data(
      caller: self(),
      reply: nil,
      mode: :session,
      proxy: true,
      client_sock: client_sock,
      stats: {0, 0},
      id: @id
    )
  end

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

  describe "TLS downstream forwarding" do
    test "chunks normal and ReadyForQuery database responses" do
      patch_sock_send()
      socket = {:ssl, :downstream}
      normal_payload = :binary.copy("x", 20_000)

      ready_payload =
        :binary.copy("y", 20_000 - byte_size(Server.ready_for_query())) <>
          Server.ready_for_query()

      assert :keep_state_and_data =
               Db.handle_event(
                 :info,
                 {:tcp, :upstream, normal_payload},
                 :busy,
                 forwarding_data(socket)
               )

      normal_chunks = receive_chunks(socket, 3)
      assert Enum.map(normal_chunks, &byte_size/1) == [8_192, 8_192, 3_616]
      assert Enum.all?(normal_chunks, &(byte_size(&1) <= @tls_send_chunk_size))
      assert IO.iodata_to_binary(normal_chunks) == normal_payload

      assert {:next_state, :idle, _} =
               Db.handle_event(
                 :info,
                 {:tcp, :upstream, ready_payload},
                 :busy,
                 forwarding_data(socket)
               )

      ready_chunks = receive_chunks(socket, 3)
      assert Enum.map(ready_chunks, &byte_size/1) == [8_192, 8_192, 3_616]
      assert Enum.all?(ready_chunks, &(byte_size(&1) <= @tls_send_chunk_size))
      assert IO.iodata_to_binary(ready_chunks) == ready_payload
    end

    test "sends TCP database responses without chunking" do
      patch_sock_send()
      socket = {:gen_tcp, :downstream}
      payload = :binary.copy("x", 20_000)

      assert :keep_state_and_data =
               Db.handle_event(
                 :info,
                 {:tcp, :upstream, payload},
                 :busy,
                 forwarding_data(socket)
               )

      assert_receive {:sock_send, ^socket, ^payload}
      refute_receive {:sock_send, ^socket, _}
    end

    test "chunks TLS client errors during termination" do
      patch_sock_send()
      socket = {:ssl, :downstream}
      fields = ["SFATAL", "VFATAL", "CXX000", "M", :binary.copy("x", 20_000)]
      message = Server.encode_error_message(fields)

      assert :ok =
               Db.terminate(
                 {:encode_and_forward, fields},
                 :busy,
                 data(id: @id, client_sock: socket)
               )

      chunks = receive_chunks(socket, 3)
      assert Enum.all?(chunks, &(byte_size(&1) <= @tls_send_chunk_size))
      assert IO.iodata_to_binary(chunks) == IO.iodata_to_binary(message)
    end

    test "stops TLS forwarding after a send error" do
      patch_sock_send({:error, :closed})
      socket = {:ssl, :downstream}
      payload = :binary.copy("x", 20_000)

      assert :keep_state_and_data =
               Db.handle_event(
                 :info,
                 {:tcp, :upstream, payload},
                 :busy,
                 forwarding_data(socket)
               )

      assert_receive {:sock_send, ^socket, first_chunk}
      assert byte_size(first_chunk) == @tls_send_chunk_size
      refute_receive {:sock_send, ^socket, _}
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
end
