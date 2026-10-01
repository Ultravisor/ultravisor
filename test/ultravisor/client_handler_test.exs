# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.ClientHandlerTest do
  use ExUnit.Case, async: true

  require Ultravisor.ClientHandler, as: CH
  require Ultravisor.Protocol.Server, as: Server

  @subject Ultravisor.ClientHandler

  test "handle ssl_error" do
    sock =
      {:sslsocket,
       {
         :gen_tcp,
         :some_port,
         :tls_connection,
         [session_id_tracker: :some_pid]
       }, [:some_pid]}

    error =
      {:ssl_error, sock,
       {
         :tls_alert,
         {:user_canceled,
          ~c"TLS server: In state connection received CLIENT ALERT: Fatal - User Canceled\n"}
       }}

    data = CH.data(sock: {:ssl, sock})

    assert :keep_state_and_data ==
             @subject.handle_event(:info, error, nil, data)
  end

  test "retains an incomplete startup packet" do
    payload = "user" <> <<0>> <> "postgres" <> <<0>>
    len = byte_size(payload) + 8
    packet = <<len::32, 196_608::32, payload::binary>>
    <<prefix::binary-size(6), suffix::binary>> = packet

    {:ok, listen} = :gen_tcp.listen(0, mode: :binary, active: false)
    {:ok, {address, port}} = :inet.sockname(listen)
    {:ok, socket} = :gen_tcp.connect(address, port, mode: :binary, active: false)
    {:ok, peer} = :gen_tcp.accept(listen)
    :ok = :gen_tcp.close(listen)
    data = CH.data(sock: {:gen_tcp, socket}, startup_buffer: <<>>)

    assert {:keep_state, CH.data(startup_buffer: ^prefix)} =
             @subject.handle_event(:info, {:tcp, socket, prefix}, :exchange, data)

    :ok = :gen_tcp.send(peer, suffix)
    assert_receive {:tcp, ^socket, ^suffix}
    :ok = :gen_tcp.close(socket)
    :ok = :gen_tcp.close(peer)
  end

  test "processes bytes after the startup frame after the greeting" do
    {:ok, listen} = :gen_tcp.listen(0, mode: :binary, active: false)
    {:ok, {address, port}} = :inet.sockname(listen)
    {:ok, socket} = :gen_tcp.connect(address, port, mode: :binary, active: false)
    {:ok, peer} = :gen_tcp.accept(listen)
    :ok = :gen_tcp.close(listen)

    data =
      CH.data(
        sock: {:gen_tcp, socket},
        mode: :transaction,
        db_pid: nil,
        prepared_statements: Ultravisor.Protocol.PreparedStatements.new(),
        ready_for_query_count: 0,
        heartbeat_interval: 0,
        idle_timeout: 0
      )

    assert {:keep_state, CH.data(ready_for_query_count: 1), []} =
             @subject.handle_event(
               :internal,
               {:startup_remainder, Server.sync()},
               :idle,
               data
             )

    assert {:ok, Server.ready_for_query()} = :gen_tcp.recv(peer, 0)
    :ok = :gen_tcp.close(socket)
    :ok = :gen_tcp.close(peer)
  end
end
