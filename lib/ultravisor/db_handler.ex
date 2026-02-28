# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.DbHandler do
  @moduledoc """
  This module contains functions to start a link with the database, send requests to the database, and handle incoming messages from clients.
  It uses the Ultravisor.Protocol.Server module to decode messages from the database and sends messages to clients Ultravisor.ClientHandler.
  """

  require Logger
  require Record

  @behaviour :gen_statem

  alias Ultravisor.ClientHandler
  alias Ultravisor.HandlerHelpers
  alias Ultravisor.Helpers
  alias Ultravisor.Monitoring.Telem
  alias Ultravisor.Protocol.Server

  @type state :: :connect | :authentication | :idle | :busy

  @reconnect_timeout 2_500
  @reconnect_timeout_proxy 500
  @sock_closed [:tcp_closed, :ssl_closed]
  @proto [:tcp, :ssl]
  @switch_active_count Application.compile_env(:ultravisor, :db_active_count)
  @reconnect_retries Application.compile_env(:ultravisor, :reconnect_retries)

  # TODO: Make it private
  Record.defrecord(:data, [
    :id,
    :sock,
    :sent,
    :auth,
    :user,
    :tenant,
    :buffer,
    :anon_buffer,
    :db_state,
    :parameter_status,
    :nonce,
    :messages,
    :server_proof,
    :stats,
    :client_stats,
    :mode,
    :replica_type,
    :reply,
    :caller,
    :client_sock,
    :proxy,
    :reconnect_retries
  ])

  @typep t() :: record(:data)

  def start_link(config),
    do: :gen_statem.start_link(__MODULE__, config, hibernate_after: 5_000)

  def checkout(pid, sock, caller, timeout \\ 15_000),
    do: :gen_statem.call(pid, {:checkout, sock, caller}, timeout)

  @spec get_state_and_mode(pid()) :: {:ok, {state, Ultravisor.mode()}} | {:error, term()}
  def get_state_and_mode(pid) do
    {:ok, :gen_statem.call(pid, :get_state_and_mode, 5_000)}
  catch
    error, reason -> {:error, {error, reason}}
  end

  @spec stop(pid()) :: :ok
  def stop(pid) do
    Logger.debug("DbHandler: Stop pid #{inspect(pid)}")
    :gen_statem.stop(pid, {:shutdown, :client_termination}, 5_000)
  end

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)
    Helpers.set_log_level(args.log_level)
    Helpers.set_max_heap_size(90)

    {_, tenant} = args.tenant
    Logger.metadata(project: tenant, user: args.user, mode: args.mode)

    data =
      data(
        id: args.id,
        sock: nil,
        sent: false,
        auth: args.auth,
        user: args.user,
        tenant: args.tenant,
        buffer: [],
        anon_buffer: [],
        db_state: nil,
        parameter_status: %{},
        nonce: nil,
        messages: "",
        server_proof: nil,
        stats: {0, 0},
        client_stats: {0, 0},
        mode: args.mode,
        replica_type: args.replica_type,
        reply: nil,
        caller: args[:caller] || nil,
        client_sock: args[:client_sock] || nil,
        proxy: args[:proxy] || false,
        reconnect_retries: 0
      )

    Telem.handler_action(:db_handler, :started, args.id)
    {:ok, :connect, data, {:next_event, :internal, :connect}}
  end

  @impl true
  def callback_mode, do: [:handle_event_function]

  @impl true
  def handle_event(:info, {passive, _socket}, _, data(sock: sock))
      when passive in [:ssl_passive, :tcp_passive] do
    HandlerHelpers.setopts(sock, active: @switch_active_count)

    :keep_state_and_data
  end

  def handle_event(
        :internal,
        _,
        :connect,
        data(id: id, client_sock: client_sock) = data
      ) do
    Logger.debug("DbHandler: Try to connect to DB")

    data(auth: auth, reconnect_retries: reconnect_retries, proxy: proxy) = data

    sock_opts =
      [
        auth.ip_version,
        buffer: 8192,
        mode: :binary,
        packet: :raw,
        # recbuf: 8192,
        # sndbuf: 8192,
        # backlog: 2048,
        # send_timeout: 120,
        # keepalive: true,
        # nopush: true,
        nodelay: true,
        active: false
      ]

    maybe_reconnect_callback = fn reason ->
      if reconnect_retries > @reconnect_retries and client_sock != nil,
        do: {:stop, {:failed_to_connect, reason}},
        else: {:keep_state_and_data, {:state_timeout, reconnect_timeout(data), :connect}}
    end

    Telem.handler_action(:db_handler, :db_connection, id)

    case :gen_tcp.connect(auth.host, auth.port, sock_opts) do
      {:ok, sock} ->
        Logger.debug("DbHandler: auth #{inspect(auth, pretty: true)}")

        case try_ssl_handshake({:gen_tcp, sock}, auth) do
          {:ok, sock} ->
            tenant = if proxy, do: Ultravisor.tenant(id)
            search_path = Ultravisor.search_path(id)

            case send_startup(sock, auth, tenant, search_path) do
              :ok ->
                HandlerHelpers.setopts(sock, active: @switch_active_count)
                {:next_state, :authentication, data(data, sock: sock)}

              {:error, reason} ->
                Logger.error("DbHandler: Send startup error #{inspect(reason)}")
                maybe_reconnect_callback.(reason)
            end

          {:error, reason} ->
            Logger.error("DbHandler: Handshake error #{inspect(reason)}")
            maybe_reconnect_callback.(reason)
        end

      other ->
        Logger.error(
          "DbHandler: Connection failed #{inspect(other)} to #{inspect(auth.host)}:#{inspect(auth.port)}"
        )

        maybe_reconnect_callback.(other)
    end
  end

  def handle_event(:state_timeout, :connect, _state, data(reconnect_retries: retry) = data) do
    Logger.warning("DbHandler: Reconnect #{retry} to DB")

    {:keep_state, data(data, reconnect_retries: retry + 1), {:next_event, :internal, :connect}}
  end

  def handle_event(:info, {proto, _, bin}, :authentication, data(id: id) = data)
      when proto in @proto do
    dec_pkt = Server.decode(bin)
    Logger.debug("DbHandler: dec_pkt, #{inspect(dec_pkt, pretty: true)}")

    resp = Enum.reduce(dec_pkt, %{}, &handle_auth_pkts(&1, &2, data))

    case resp do
      {:authentication_sasl, nonce} ->
        {:keep_state, data(data, nonce: nonce)}

      {:authentication_server_first_message, server_proof} ->
        {:keep_state, data(data, server_proof: server_proof)}

      %{authentication_server_final_message: _server_final} ->
        :keep_state_and_data

      %{authentication_ok: true} ->
        :keep_state_and_data

      :authentication ->
        :keep_state_and_data

      :authentication_md5 ->
        :keep_state_and_data

      {:error_response, ["SFATAL", "VFATAL", "C28P01", reason, _, _, _]} ->
        handle_authentication_error(data, reason)
        Logger.error("DbHandler: Auth error #{inspect(reason)}")
        {:stop, :invalid_password, data}

      {:error_response, error} ->
        Logger.error("DbHandler: Error auth response #{inspect(error)}")
        {:stop, {:encode_and_forward, error}}

      {:ready_for_query, acc} ->
        ps = acc.ps

        Logger.debug(
          "DbHandler: DB ready_for_query: #{inspect(acc.db_state)} #{inspect(ps, pretty: true)}"
        )

        data(proxy: proxy, caller: caller) = data

        if proxy do
          bin_ps = Server.encode_parameter_status(ps)
          send(caller, {:parameter_status, bin_ps})
        else
          Ultravisor.set_parameter_status(id, ps)
        end

        {:next_state, :idle, data(data, parameter_status: ps, reconnect_retries: 0),
         {:next_event, :internal, :check_buffer}}

      other ->
        Logger.error("DbHandler: Undefined auth response #{inspect(other)}")
        {:stop, :auth_error, data}
    end
  end

  def handle_event(:internal, :check_buffer, :idle, data(sock: sock, reply: from) = data)
      when from != nil do
    Logger.debug("DbHandler: Check buffer")
    {:next_state, :busy, data(data, reply: nil), {:reply, from, sock}}
  end

  def handle_event(
        :internal,
        :check_buffer,
        :idle,
        data(sock: sock, buffer: buff, caller: caller) = data
      )
      when is_pid(caller) do
    if buff != [] do
      Logger.debug("DbHandler: Buffer is not empty, try to send #{IO.iodata_length(buff)} bytes")
      buff = Enum.reverse(buff)
      :ok = sock_send(sock, buff)
    end

    {:next_state, :busy, data(data, buffer: [])}
  end

  # check if it needs to apply queries from the anon buffer
  def handle_event(
        :internal,
        :check_anon_buffer,
        _,
        data(sock: sock, anon_buffer: buff, caller: nil) = data
      ) do
    Logger.debug("DbHandler: Check anon buffer")

    if buff != [] do
      Logger.debug(
        "DbHandler: Anon buffer is not empty, try to send #{IO.iodata_length(buff)} bytes"
      )

      buff = Enum.reverse(buff)
      :ok = sock_send(sock, buff)
    end

    {:keep_state, data(data, anon_buffer: [])}
  end

  def handle_event(:internal, :check_anon_buffer, _, _) do
    Logger.debug("DbHandler: Anon buffer is empty")
    :keep_state_and_data
  end

  # the process received message from db without linked caller
  def handle_event(:info, {proto, _, bin}, _, data(caller: nil)) when proto in @proto do
    Logger.debug("DbHandler: Got db response #{inspect(bin)} when caller was nil")
    :keep_state_and_data
  end

  def handle_event(:info, {proto, _, bin}, _, data(id: id, replica_type: :read) = data)
      when proto in @proto do
    Logger.debug("DbHandler: Got read replica message #{inspect(bin)}")
    pkts = Server.decode(bin)

    resp =
      cond do
        Server.has_read_only_error?(pkts) ->
          Logger.error("DbHandler: read only error")

          with [_] <- pkts do
            # need to flush ready_for_query if it's not in same packet
            :ok = receive_ready_for_query()
          end

          :read_sql_error

        List.last(pkts).tag == :ready_for_query ->
          :ready_for_query

        true ->
          :continue
      end

    if resp != :continue do
      data(caller: caller, sock: sock, stats: stats) = data

      :ok = ClientHandler.db_status(caller, resp, bin)
      {_, stats} = Telem.network_usage(:db, sock, id, stats)
      {:keep_state, data(data, stats: stats, caller: handler_caller(data))}
    else
      :keep_state_and_data
    end
  end

  # forward the message to the client
  def handle_event(:info, {proto, _, bin}, _, data(id: id, caller: caller, reply: nil) = data)
      when is_pid(caller) and proto in @proto do
    Logger.debug("DbHandler: Got write replica message  #{inspect(bin)}")

    if String.ends_with?(bin, Server.ready_for_query()) do
      data(
        sock: sock,
        client_sock: client_sock,
        mode: mode,
        proxy: proxy,
        stats: stats,
        client_stats: client_stats
      ) = data

      {_, stats} =
        if proxy,
          do: {nil, stats},
          else: Telem.network_usage(:db, sock, id, stats)

      # in transaction mode, we need to notify the client when the transaction is finished,
      # after which it will unlink the direct db connection process from itself.
      data =
        if mode == :transaction do
          ClientHandler.db_status(caller, :ready_for_query, bin)
          data(data, stats: stats, caller: nil, client_sock: nil)
        else
          HandlerHelpers.sock_send(client_sock, bin)

          {_, client_stats} =
            if proxy,
              do: {nil, client_stats},
              else: Telem.network_usage(:client, client_sock, id, client_stats)

          data(data, stats: stats, client_stats: client_stats)
        end

      {:next_state, :idle, data, {:next_event, :internal, :check_anon_buffer}}
    else
      HandlerHelpers.sock_send(data(data, :client_sock), bin)
      {:keep_state, data}
    end
  end

  def handle_event(
        {:call, from},
        {:checkout, client_sock, caller},
        state,
        data(sock: sock) = data
      ) do
    Logger.debug("DbHandler: checkout call when state was #{state}")

    # store the reply ref and send it when the state is idle
    if state in [:idle, :busy],
      do:
        {:keep_state, data(data, client_sock: client_sock, caller: caller), {:reply, from, sock}},
      else: {:keep_state, data(data, client_sock: client_sock, caller: caller, reply: from)}
  end

  def handle_event({:call, from}, :ps, _, data(parameter_status: parameter_status)) do
    Logger.debug("DbHandler: get parameter status")
    {:keep_state_and_data, {:reply, from, parameter_status}}
  end

  def handle_event(_, {closed, _}, :busy, data) when closed in @sock_closed do
    {:stop, {:shutdown, :db_termination}, data}
  end

  def handle_event(_, {closed, _}, state, data) when closed in @sock_closed do
    Logger.error("DbHandler: Connection closed when state was #{state}")

    if Application.get_env(:ultravisor, :reconnect_on_db_close),
      do: {:next_state, :connect, data, {:state_timeout, reconnect_timeout(data), :connect}},
      else: {:stop, {:shutdown, :db_termination}, data}
  end

  # linked client_handler went down
  def handle_event(_, {:EXIT, pid, reason}, state, data(mode: mode, sock: sock) = data) do
    if reason != :normal do
      Logger.error(
        "DbHandler: ClientHandler #{inspect(pid)} went down with reason #{inspect(reason)}"
      )
    end

    if state == :busy or mode == :session do
      sock_send(sock, Server.terminate_message())
      :gen_tcp.close(elem(sock, 1))
      {:stop, {:client_handler_down, mode}}
    else
      {:keep_state, data(data, caller: nil, buffer: [])}
    end
  end

  def handle_event({:call, from}, :get_state_and_mode, state, data) do
    {:keep_state_and_data, {:reply, from, {state, data(data, :mode)}}}
  end

  def handle_event(type, content, state, data() = data) do
    msg = [
      {"type", type},
      {"content", content},
      {"state", state},
      {"data", data}
    ]

    Logger.error("DbHandler: Undefined msg: #{inspect(msg, pretty: true)}")

    :keep_state_and_data
  end

  @impl true
  def terminate(:shutdown, _state, data(id: id)) do
    Telem.handler_action(:db_handler, :stopped, id)
    :ok
  end

  def terminate(reason, state, data(id: id, client_sock: client_sock)) do
    Telem.handler_action(:db_handler, :stopped, id)

    if client_sock != nil do
      message =
        case reason do
          {:encode_and_forward, msg} -> Server.encode_error_message(msg)
          _ -> Server.error_message("XX000", inspect(reason))
        end

      HandlerHelpers.sock_send(client_sock, message)
    end

    Logger.error(
      "DbHandler: Terminating with reason #{inspect(reason)} when state was #{inspect(state)}"
    )
  end

  @spec try_ssl_handshake(Ultravisor.tcp_sock(), map) ::
          {:ok, Ultravisor.sock()} | {:error, term()}
  defp try_ssl_handshake(sock, %{upstream_ssl: true} = auth) do
    case sock_send(sock, Server.ssl_request()) do
      :ok -> ssl_recv(sock, auth)
      error -> error
    end
  end

  defp try_ssl_handshake(sock, _), do: {:ok, sock}

  @spec ssl_recv(Ultravisor.tcp_sock(), map) :: {:ok, Ultravisor.ssl_sock()} | {:error, term}
  defp ssl_recv({:gen_tcp, sock} = s, auth) do
    case :gen_tcp.recv(sock, 1, 15_000) do
      {:ok, <<?S>>} -> ssl_connect(s, auth)
      {:ok, <<?N>>} -> {:error, :ssl_not_available}
      {:error, _} = error -> error
    end
  end

  @spec ssl_connect(Ultravisor.tcp_sock(), map, pos_integer) ::
          {:ok, Ultravisor.ssl_sock()} | {:error, term}
  defp ssl_connect({:gen_tcp, sock}, auth, timeout \\ 5000) do
    opts =
      case auth.upstream_verify do
        :peer ->
          [
            verify: :verify_peer,
            cacerts: [auth.upstream_tls_ca],
            # unclear behavior on pg14
            server_name_indication: auth.sni_hostname || auth.host,
            customize_hostname_check: [{:match_fun, fn _, _ -> true end}]
          ]

        :none ->
          [verify: :verify_none]
      end

    case :ssl.connect(sock, opts, timeout) do
      {:ok, ssl_sock} ->
        {:ok, {:ssl, ssl_sock}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec send_startup(Ultravisor.sock(), map(), String.t() | nil, String.t() | nil) ::
          :ok | {:error, term}
  def send_startup(sock, auth, tenant, search_path) do
    user =
      if is_nil(tenant), do: get_user(auth), else: "#{get_user(auth)}.#{tenant}"

    msg =
      :pgo_protocol.encode_startup_message(
        [
          {"user", user},
          {"database", auth.database},
          {"application_name", auth.application_name}
        ] ++ if(search_path, do: [{"options", "--search_path=#{search_path}"}], else: [])
      )

    sock_send(sock, msg)
  end

  @spec sock_send(Ultravisor.sock(), iodata) :: :ok | {:error, term}
  defp sock_send({mod, sock}, data) do
    mod.send(sock, data)
  end

  defp get_user(auth) do
    if auth.require_user do
      auth.secrets.().db_user
    else
      auth.secrets.().user
    end
  end

  @spec receive_ready_for_query() :: :ok | :timeout_error
  defp receive_ready_for_query do
    receive do
      {_proto, _socket, <<?Z, 5::32, ?I>>} ->
        :ok
    after
      15_000 -> :timeout_error
    end
  end

  @spec handler_caller(t()) :: pid() | nil
  defp handler_caller(data(caller: caller, mode: :session)), do: caller
  defp handler_caller(_), do: nil

  @spec check_ready(binary()) ::
          {:ready_for_query, :idle | :transaction_block | :failed_transaction_block} | :continue
  def check_ready(bin) do
    bin_size = byte_size(bin)

    case bin do
      <<_::binary-size(bin_size - 6), 90, 0, 0, 0, 5, status_indicator::binary>> ->
        indicator =
          case status_indicator do
            <<?I>> -> :idle
            <<?T>> -> :transaction_block
            <<?E>> -> :failed_transaction_block
            _ -> :continue
          end

        {:ready_for_query, indicator}

      _ ->
        :continue
    end
  end

  @spec handle_auth_pkts(map(), map(), t()) :: any()
  defp handle_auth_pkts(%{tag: :parameter_status, payload: {k, v}}, acc, _),
    do: update_in(acc, [:ps], fn ps -> Map.put(ps || %{}, k, v) end)

  defp handle_auth_pkts(%{tag: :ready_for_query, payload: db_state}, acc, _),
    do: {:ready_for_query, Map.put(acc, :db_state, db_state)}

  defp handle_auth_pkts(%{tag: :backend_key_data, payload: payload}, acc, data(auth: auth)) do
    key = self()
    conn = %{host: auth.host, port: auth.port, ip_ver: auth.ip_version}
    Registry.register(Ultravisor.Registry.PoolPids, key, Map.merge(payload, conn))
    Logger.debug("DbHandler: Backend #{inspect(key)} data: #{inspect(payload)}")
    Map.put(acc, :backend_key_data, payload)
  end

  defp handle_auth_pkts(
         %{payload: {:authentication_sasl_password, methods_b}},
         _,
         data(auth: auth, sock: sock)
       ) do
    nonce =
      case Server.decode_string(methods_b) do
        {:ok, req_method, _} ->
          Logger.debug("DbHandler: SASL method #{inspect(req_method)}")
          nonce = :pgo_scram.get_nonce(16)
          user = get_user(auth)
          client_first = :pgo_scram.get_client_first(user, nonce)
          client_first_size = IO.iodata_length(client_first)

          sasl_initial_response = [
            "SCRAM-SHA-256",
            0,
            <<client_first_size::32-integer>>,
            client_first
          ]

          bin = :pgo_protocol.encode_scram_response_message(sasl_initial_response)
          :ok = HandlerHelpers.sock_send(sock, bin)
          nonce

        other ->
          Logger.error("DbHandler: Undefined sasl method #{inspect(other)}")
          nil
      end

    {:authentication_sasl, nonce}
  end

  defp handle_auth_pkts(
         %{payload: {:authentication_server_first_message, server_first}},
         _,
         data(auth: auth, nonce: nonce, sock: sock)
       )
       when auth.require_user == false do
    server_first_parts = Helpers.parse_server_first(server_first, nonce)

    {client_final_message, server_proof} =
      Helpers.get_client_final(
        :auth_query,
        auth.secrets.(),
        server_first_parts,
        nonce,
        auth.secrets.().user,
        "biws"
      )

    bin = :pgo_protocol.encode_scram_response_message(client_final_message)
    :ok = HandlerHelpers.sock_send(sock, bin)

    {:authentication_server_first_message, server_proof}
  end

  defp handle_auth_pkts(
         %{payload: {:authentication_server_first_message, server_first}},
         _,
         data(auth: auth, nonce: nonce, sock: sock)
       ) do
    server_first_parts = :pgo_scram.parse_server_first(server_first, nonce)

    {client_final_message, server_proof} =
      :pgo_scram.get_client_final(
        server_first_parts,
        nonce,
        auth.user,
        auth.secrets.().password
      )

    bin = :pgo_protocol.encode_scram_response_message(client_final_message)
    :ok = HandlerHelpers.sock_send(sock, bin)

    {:authentication_server_first_message, server_proof}
  end

  defp handle_auth_pkts(
         %{payload: {:authentication_server_final_message, server_final}},
         acc,
         _data
       ),
       do: Map.put(acc, :authentication_server_final_message, server_final)

  defp handle_auth_pkts(
         %{payload: :authentication_ok},
         acc,
         _data
       ),
       do: Map.put(acc, :authentication_ok, true)

  defp handle_auth_pkts(
         %{payload: {:authentication_md5_password, salt}} = dec_pkt,
         _,
         data(auth: auth, sock: sock)
       ) do
    Logger.debug("DbHandler: dec_pkt, #{inspect(dec_pkt, pretty: true)}")

    digest =
      if auth.method == :password do
        Helpers.md5([auth.password.(), auth.user])
      else
        auth.secrets.().secret
      end

    payload = ["md5", Helpers.md5([digest, salt]), 0]
    bin = [?p, <<IO.iodata_length(payload) + 4::signed-32>>, payload]
    :ok = HandlerHelpers.sock_send(sock, bin)
    :authentication_md5
  end

  defp handle_auth_pkts(%{tag: :error_response, payload: error}, _acc, _data),
    do: {:error_response, error}

  defp handle_auth_pkts(_e, acc, _data), do: acc

  @spec handle_authentication_error(t(), String.t()) :: any()
  defp handle_authentication_error(data(id: id, user: user, proxy: false), reason) do
    tenant = Ultravisor.tenant(id)

    :erpc.multicast([node() | Node.list()], fn ->
      Cachex.del(Ultravisor.Cache, {:secrets, tenant, user})
      Cachex.del(Ultravisor.Cache, {:secrets_check, tenant, user})

      Registry.dispatch(Ultravisor.Registry.TenantClients, id, fn entries ->
        for {client_handler, _meta} <- entries,
            do: send(client_handler, {:disconnect, reason})
      end)
    end)

    Ultravisor.stop(id)
  end

  defp handle_authentication_error(data(proxy: true), _reason), do: :ok

  @spec reconnect_timeout(t()) :: pos_integer()
  defp reconnect_timeout(data(proxy: true)),
    do: @reconnect_timeout_proxy

  defp reconnect_timeout(_),
    do: @reconnect_timeout
end
