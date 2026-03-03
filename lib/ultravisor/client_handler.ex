# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.ClientHandler do
  @moduledoc """
  This module is responsible for handling incoming connections to the Ultravisor server. It is
  implemented as a Ranch protocol behavior and a gen_statem behavior. It handles SSL negotiation,
  user authentication, tenant subscription, and dispatching of messages to the appropriate tenant
  supervisor. Each client connection is assigned to a specific tenant supervisor.
  """

  @behaviour :ranch_protocol
  @behaviour :gen_statem

  @proto [:tcp, :ssl]

  @switch_active_count Application.compile_env(:ultravisor, :client_active_count)
  @subscribe_retries Application.compile_env(:ultravisor, :subscribe_retries)

  @timeout_subscribe 500
  @clients_registry Ultravisor.Registry.TenantClients
  @proxy_clients_registry Ultravisor.Registry.TenantProxyClients

  require Logger
  require Record

  require Ultravisor.Protocol.Server, as: Server

  import Ultravisor, only: [conn_id: 2]

  alias Ultravisor.DbHandler
  alias Ultravisor.HandlerHelpers
  alias Ultravisor.Helpers
  alias Ultravisor.Monitoring.Telem

  alias Ultravisor.Protocol.Error
  alias Ultravisor.Protocol.Errors

  # TODO: remove all tests that rely on this structure and replace them with
  # something more appropriate
  Record.defrecord(:data, [
    :id,
    :sock,
    :db_pid,
    :pool,
    :manager,
    :query_start,
    :timeout,
    :ps,
    :ssl,
    :auth_secrets,
    :mode,
    :stats,
    :idle_timeout,
    :last_query,
    :heartbeat_interval,
    :connection_start,
    :log_level,
    :auth,
    :tenant_availability_zone,
    :local,
    :app_name
  ])

  @typep t() :: record(:data)

  @impl true
  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [ref, transport, opts])
    {:ok, pid}
  end

  @impl true
  def callback_mode, do: [:handle_event_function, :state_enter]

  @spec db_status(pid(), :ready_for_query, binary()) :: :ok
  def db_status(pid, status, bin), do: :gen_statem.cast(pid, {:db_status, status, bin})

  def save_stats(pid), do: :gen_statem.cast(pid, :save_stats)

  @impl true
  def init(_), do: :ignore

  def init(ref, trans, opts) do
    Process.flag(:trap_exit, true)
    Helpers.set_max_heap_size(90)

    {:ok, sock} = :ranch.handshake(ref)
    peer_ip = Helpers.peer_ip(sock)
    local = opts[:local] || false

    Logger.metadata(
      peer_ip: peer_ip,
      local: local,
      state: :init
    )

    :ok =
      trans.setopts(sock,
        # mode: :binary,
        # packet: :raw,
        # recbuf: 8192,
        # sndbuf: 8192,
        # # backlog: 2048,
        # send_timeout: 120,
        # keepalive: true,
        # nodelay: true,
        # nopush: true,
        active: :once
      )

    Logger.debug("ClientHandler is: #{inspect(self())}")

    data =
      data(
        id: nil,
        sock: {:gen_tcp, sock},
        db_pid: nil,
        pool: nil,
        manager: nil,
        query_start: nil,
        timeout: nil,
        ps: nil,
        ssl: false,
        auth_secrets: nil,
        mode: opts.mode,
        stats: {0, 0},
        idle_timeout: 0,
        last_query: nil,
        heartbeat_interval: 0,
        connection_start: System.monotonic_time(),
        log_level: nil,
        auth: %{},
        tenant_availability_zone: nil,
        local: local,
        app_name: nil
      )

    :gen_statem.enter_loop(__MODULE__, [hibernate_after: 5_000], :exchange, data)
  end

  @impl true
  def handle_event(:enter, old, new, data) do
    :logger.update_process_metadata(%{state: new})

    if old == :idle do
      # If previous state was idle, then do not even attempt to store network
      # stats, as there should be next to no data transferred
      {:next_state, new, data}
    else
      {:next_state, new, net_stats(data)}
    end
  end

  def handle_event(:info, {passive, _socket}, _, data(sock: sock))
      when passive in [:ssl_passive, :tcp_passive] do
    HandlerHelpers.setopts(sock, active: @switch_active_count)

    :keep_state_and_data
  end

  # cancel request
  def handle_event(:info, {_, _, Server.cancel_message(pid, key)}, _state, _) do
    Logger.debug("ClientHandler: Got cancel query for #{inspect({pid, key})}")
    :ok = HandlerHelpers.send_cancel_query(pid, key)
    {:stop, {:shutdown, :cancel_query}}
  end

  # send cancel request to db
  def handle_event(:info, :cancel_query, :busy, data) do
    data(id: id, db_pid: db_pid) = data
    key = {conn_id(id, :tenant), db_pid}
    Logger.debug("ClientHandler: Cancel query for #{inspect(key)}")
    {_pool, db_pid, _db_sock} = db_pid

    case db_pid_meta(key) do
      [{^db_pid, meta}] ->
        :ok = HandlerHelpers.cancel_query(meta.host, meta.port, meta.ip_ver, meta.pid, meta.key)

      error ->
        Logger.error(
          "ClientHandler: Received cancel but no proc was found #{inspect(key)} #{inspect(error)}"
        )
    end

    :keep_state_and_data
  end

  def handle_event(:info, {_proto, _, _data} = msg, :exchange, data) do
    case Ultravisor.ClientHandler.Exchange.handle(msg, data) do
      {:ok, conn_type, data(id: id, sock: sock) = data} ->
        :ok = HandlerHelpers.sock_send(sock, Server.authentication_ok())
        Telem.client_join(:ok, id)
        HandlerHelpers.setopts(sock, active: @switch_active_count)
        {:keep_state, data, {:next_event, :internal, conn_type}}

      {:upgrade, ssl_sock} ->
        HandlerHelpers.setopts(ssl_sock, active: :once)
        {:keep_state, data(data, sock: ssl_sock, ssl: true)}

      {:no_upgrade, sock} ->
        HandlerHelpers.setopts(sock, active: :once)
        {:keep_state, data(data, sock: sock, ssl: false)}

      {:error, :http_request} ->
        Logger.debug("ClientHandler: Client is trying to request HTTP")

        HandlerHelpers.sock_send(
          data(data, :sock),
          ["HTTP/1.1 204 OK\r\nx-app-version: ", Application.spec(:ultravisor, :vsn), "\r\n\r\n"]
        )

        {:stop, {:shutdown, :http_request}}

      {:error, %_{} = error, _data} ->
        msg = Ultravisor.Protocol.Error.encode(error)

        HandlerHelpers.sock_send(data(data, :sock), msg)

        {:stop, {:shutdown, error}}

      {:error, other, data(id: id)} ->
        Telem.client_join(:fail, id)
        {:stop, {:shutdown, other}}
    end
  end

  def handle_event(:internal, {:subscribe, retries}, _state, data(id: id, sock: sock) = data)
      when retries < @subscribe_retries do
    Logger.debug("ClientHandler: Subscribe to tenant #{inspect(id)}")

    data(
      auth: auth,
      auth_secrets: auth_secrets,
      log_level: log_level,
      tenant_availability_zone: availability_zone,
      mode: mode
    ) = data

    with {:ok, sup} <-
           Ultravisor.start_dist(id, auth_secrets,
             log_level: log_level,
             availability_zone: availability_zone
           ),
         true <-
           if(node(sup) != node() and mode in [:transaction, :session],
             do: :proxy,
             else: true
           ),
         {:ok, opts} <- Ultravisor.subscribe(sup, id) do
      manager_ref = Process.monitor(opts.workers.manager)
      data = data(data, manager: opts.workers.manager, pool: opts.workers.pool)
      db_pid = db_checkout(:on_connect, data)
      data = data(data, manager: manager_ref, db_pid: db_pid, idle_timeout: opts.idle_timeout)

      Registry.register(@clients_registry, id, [])

      next =
        if opts.ps == [],
          do: {:timeout, 10_000, :wait_ps},
          else: {:next_event, :internal, {:greetings, opts.ps}}

      {:keep_state, data, next}
    else
      {:error, :max_clients_reached} ->
        msg = "Max client connections reached"
        Logger.error("ClientHandler: #{msg}")
        :ok = HandlerHelpers.send_error(sock, "XX000", msg)
        Telem.client_join(:fail, id)
        {:stop, {:shutdown, :max_clients_reached}}

      {:error, :max_pools_reached} ->
        msg = "Max pools count reached"
        Logger.error("ClientHandler: #{msg}")
        :ok = HandlerHelpers.send_error(sock, "XX000", msg)
        Telem.client_join(:fail, id)
        {:stop, {:shutdown, :max_pools_reached}}

      :proxy ->
        case Ultravisor.get_pool_ranch(id) do
          {:ok, %{port: port, host: host}} ->
            auth =
              Map.merge(auth, %{
                port: port,
                host: to_charlist(host),
                ip_version: :inet,
                upstream_ssl: false,
                upstream_tls_ca: nil,
                upstream_verify: nil
              })

            Logger.metadata(proxy: true)
            Registry.register(@proxy_clients_registry, id, [])

            {:keep_state, data(data, auth: auth), {:next_event, :internal, :connect_db}}

          other ->
            Logger.error("ClientHandler: Subscribe proxy error: #{inspect(other)}")
            {:keep_state, data, {:timeout, @timeout_subscribe, {:subscribe, retries + 1}}}
        end

      error ->
        Logger.error("ClientHandler: Subscribe error: #{inspect(error)}")
        {:keep_state, data, {:timeout, @timeout_subscribe, {:subscribe, retries + 1}}}
    end
  rescue
    exception ->
      msg = Error.encode(exception, __STACKTRACE__)
      data(sock: sock) = data
      HandlerHelpers.sock_send(sock, msg)

      reraise exception, __STACKTRACE__
  end

  def handle_event(:internal, {:subscribe, retries}, _state, _data) do
    Logger.error("ClientHandler: Terminate after #{retries} retries")
    {:stop, {:shutdown, :subscribe_retries}}
  end

  def handle_event(:internal, :connect_db, _state, data) do
    Logger.debug("ClientHandler: Trying to connect to DB")

    data(id: id, auth: auth, log_level: log_level, sock: sock) = data

    args = %{
      id: id,
      auth: auth,
      user: conn_id(id, :user),
      tenant: {:single, conn_id(id, :tenant)},
      mode: :proxy,
      proxy: true,
      log_level: log_level,
      caller: self(),
      client_sock: sock
    }

    {:ok, db_pid} = DbHandler.start_link(args)
    db_sock = DbHandler.checkout(db_pid, sock)
    {:keep_state, data(data, db_pid: {nil, db_pid, db_sock}, mode: :proxy)}
  end

  def handle_event(:internal, {:greetings, ps}, _state, data(id: id, sock: sock) = data) do
    {header, <<pid::32, key::32>> = payload} = Server.backend_key_data()
    msg = [ps, [header, payload], Server.ready_for_query()]
    :ok = HandlerHelpers.listen_cancel_query(pid, key)
    :ok = HandlerHelpers.sock_send(sock, msg)
    Telem.client_connection_time(data(data, :connection_start), id)
    {:next_state, :idle, data, handle_actions(data)}
  end

  def handle_event(:timeout, {:subscribe, retries}, _state, _) do
    {:keep_state_and_data, {:next_event, :internal, {:subscribe, retries}}}
  end

  def handle_event(:timeout, :wait_ps, _state, data(ps: ps)) do
    Logger.error("ClientHandler: Wait parameter status timeout, send default #{inspect(ps)}}")

    ps = Server.encode_parameter_status(ps)
    {:keep_state_and_data, {:next_event, :internal, {:greetings, ps}}}
  end

  def handle_event(:timeout, :idle_terminate, _state, data) do
    Logger.warning(
      "ClientHandler: Terminate an idle connection by #{data(data, :idle_timeout)} timeout"
    )

    {:stop, {:shutdown, :idle_terminate}}
  end

  def handle_event(:timeout, :heartbeat_check, _state, data(sock: sock, heartbeat_interval: hb)) do
    Logger.debug("ClientHandler: Send heartbeat to client")
    HandlerHelpers.sock_send(sock, Server.application_name())
    {:keep_state_and_data, {:timeout, hb, :heartbeat_check}}
  end

  def handle_event(:info, {proto, _socket, msg}, state, data)
      when proto in @proto and is_binary(msg) do
    handle_downstream_data(msg, state, data)
  rescue
    exception ->
      msg = Error.encode(exception, __STACKTRACE__)
      data(sock: sock) = data
      HandlerHelpers.sock_send(sock, msg)

      reraise exception, __STACKTRACE__
  end

  def handle_event(:info, {:parameter_status, :updated}, _state, _) do
    Logger.warning("ClientHandler: Parameter status is updated")
    {:stop, {:shutdown, :parameter_status_updated}}
  end

  def handle_event(:info, {:parameter_status, ps}, :exchange, _) do
    {:keep_state_and_data, {:next_event, :internal, {:greetings, ps}}}
  end

  def handle_event(:info, {:ssl_error, sock, reason}, _, data(sock: {_, sock})) do
    Logger.error("ClientHandler: TLS error #{inspect(reason)}")
    :keep_state_and_data
  end

  # client closed connection
  def handle_event(_, {closed, _}, _state, data(id: id))
      when closed in [:tcp_closed, :ssl_closed] do
    Logger.debug("ClientHandler: #{closed} socket closed for #{inspect(conn_id(id, :tenant))}")

    {:stop, {:shutdown, :socket_closed}}
  end

  # linked DbHandler went down
  def handle_event(:info, {:EXIT, db_pid, reason}, _state, data(sock: sock)) do
    Logger.error("ClientHandler: DbHandler #{inspect(db_pid)} exited #{inspect(reason)}")
    HandlerHelpers.sock_send(sock, Server.error_message("XX000", "DbHandler exited"))
    {:stop, {:shutdown, :db_handler_exit}}
  end

  # pool's manager went down
  def handle_event(:info, {:DOWN, ref, _, _, reason}, state, data(manager: ref)) do
    Logger.error(
      "ClientHandler: Manager #{inspect(ref)} went down #{inspect(reason)} state #{inspect(state)}"
    )

    case {state, reason} do
      {_, :shutdown} -> {:stop, {:shutdown, :manager_shutdown}}
      {:idle, _} -> {:keep_state_and_data, {:next_event, :internal, {:subscribe, 0}}}
      {:busy, _} -> {:stop, {:shutdown, :manager_down}}
    end
  end

  def handle_event(:info, {:disconnect, reason}, _state, _data) do
    Logger.warning("ClientHandler: Disconnected due to #{inspect(reason)}")
    {:stop, {:shutdown, {:disconnect, reason}}}
  end

  # emulate handle_cast
  def handle_event(:cast, {:db_status, status, bin}, :busy, data() = data) do
    data(
      id: id,
      sock: sock,
      pool: pool,
      mode: mode,
      db_pid: db_pid,
      query_start: query_start
    ) = data

    case status do
      :ready_for_query ->
        Logger.debug("ClientHandler: Client is ready")

        :ok = HandlerHelpers.sock_send(sock, bin)

        db_pid = db_checkin(mode, pool, db_pid)

        Telem.client_query_time(query_start, id)

        {:next_state, :idle, data(data, db_pid: db_pid), handle_actions(data)}
    end
  end

  def handle_event(:cast, :save_stats, _, data) do
    {:keep_state, net_stats(data)}
  end

  def handle_event(:info, {sock_error, _sock, msg}, _state, _data)
      when sock_error in [:tcp_error, :ssl_error] do
    Logger.error("ClientHandler: Socket error: #{inspect(msg)}")

    {:stop, {:shutdown, {:socket_error, msg}}}
  end

  def handle_event(type, content, _state, _data) do
    msg = [
      {"type", type},
      {"content", content}
    ]

    Logger.error("ClientHandler: Undefined msg: #{inspect(msg, pretty: true)}")

    :keep_state_and_data
  end

  @impl true
  def terminate(reason, _state, data(db_pid: {_, pid, _})) do
    db_info =
      with {:ok, {state, mode} = resp} <- DbHandler.get_state_and_mode(pid) do
        if state == :busy or mode == :session, do: DbHandler.stop(pid)
        resp
      end

    Logger.debug(
      "ClientHandler: socket closed with reason #{inspect(reason)}, DbHandler #{inspect({pid, db_info})}"
    )

    :ok
  end

  def terminate(reason, _state, _data) do
    Logger.debug("ClientHandler: socket closed with reason #{inspect(reason)}")
    :ok
  end

  ## Internal functions

  @spec db_checkout(:on_connect | :on_query, t()) ::
          {pid, pid, Ultravisor.sock()} | nil
  defp db_checkout(_, data(mode: mode, db_pid: {pool, db_pid, db_sock}))
       when is_pid(db_pid) and mode in [:session, :proxy] do
    {pool, db_pid, db_sock}
  end

  defp db_checkout(:on_connect, data(mode: :transaction)), do: nil

  defp db_checkout(_, data) do
    data(id: id, sock: sock, pool: pool, mode: mode, timeout: timeout) = data
    start = System.monotonic_time()

    db_pid =
      case :poolboy.checkout(pool, timeout) do
        {:ok, db_pid} -> db_pid
        _ when mode == :transaction -> raise Errors.CheckoutTimeoutError
        _ when mode == :session -> raise Errors.MaxClientConnectionsError
      end

    Process.link(db_pid)
    db_sock = DbHandler.checkout(db_pid, sock)
    same_box = if node(db_pid) == node(), do: :local, else: :remote
    Telem.pool_checkout_time(System.monotonic_time() - start, id, same_box)
    {pool, db_pid, db_sock}
  end

  @spec db_checkin(:transaction, pid(), pid() | nil) :: nil
  @spec db_checkin(:session, pid(), pid()) :: pid()
  @spec db_checkin(:proxy, pid(), pid()) :: pid()
  defp db_checkin(:transaction, _pool, nil), do: nil

  defp db_checkin(:transaction, pool, {_, db_pid, _}) do
    Process.unlink(db_pid)
    :poolboy.checkin(pool, db_pid)
    nil
  end

  defp db_checkin(:session, _, db_pid), do: db_pid
  defp db_checkin(:proxy, _, db_pid), do: db_pid

  defp db_pid_meta({_, {_, pid, _}} = _key) do
    rkey = Ultravisor.Registry.PoolPids
    fnode = node(pid)

    if fnode == node() do
      Registry.lookup(rkey, pid)
    else
      :erpc.call(fnode, Registry, :lookup, [rkey, pid], 15_000)
    end
  end

  @spec handle_downstream_data(data :: binary(), state, data) ::
          :gen_statem.event_handler_result(data)
        when state: atom() | term(),
             data: term()

  # handle Terminate message
  defp handle_downstream_data(Server.terminate(), :idle, data(local: true)) do
    Logger.info("ClientHandler: Terminate received from proxy client")
    :keep_state_and_data
  end

  defp handle_downstream_data(Server.terminate(), :idle, _data) do
    Logger.info("ClientHandler: Terminate received from client")
    {:stop, {:shutdown, :terminate_received}}
  end

  defp handle_downstream_data(Server.sync(), :idle, data(sock: sock, db_pid: db_pid) = data) do
    Logger.debug("ClientHandler: Receive sync")

    # db_pid can be nil in transaction mode, so we will send ready_for_query
    # without checking out a direct connection. If there is a linked db_pid,
    # we will forward the message to it
    if db_pid,
      do: :ok = HandlerHelpers.sock_send(sock, Server.ready_for_query()),
      else: :ok = forward_to_db(Server.sync(), data)

    {:keep_state, data, handle_actions(data)}
  end

  defp handle_downstream_data(Server.sync(), _, data) do
    Logger.debug("ClientHandler: Receive sync while not idle")
    :ok = forward_to_db(Server.sync(), data)
    {:keep_state, data, handle_actions(data)}
  end

  # handle Flush message
  defp handle_downstream_data(Server.flush(), _, data) do
    Logger.debug("ClientHandler: Receive flush while not idle")
    :ok = forward_to_db(Server.flush(), data)
    {:keep_state, data, handle_actions(data)}
  end

  # incoming query with a single pool
  defp handle_downstream_data(bin, :idle, data(pool: pid) = data) when is_pid(pid) do
    Logger.debug("ClientHandler: Receive query #{inspect(bin)}")
    db_pid = db_checkout(:on_query, data)
    data = data(data, db_pid: db_pid, query_start: System.monotonic_time())

    :ok = forward_to_db(bin, data)

    {:next_state, :busy, data}
  end

  defp handle_downstream_data(bin, _, data(mode: :proxy) = data) do
    data = data(data, query_start: System.monotonic_time())
    :ok = forward_to_db(bin, data)
    {:next_state, :busy, data}
  end

  # incoming query with read/write pools
  defp handle_downstream_data(bin, :idle, data) do
    ts = System.monotonic_time()
    db_pid = db_checkout(:on_query, data)
    data = data(data, db_pid: db_pid, query_start: ts, last_query: "")

    :ok = forward_to_db(bin, data)

    {:next_state, :busy, data}
  end

  # forward query to db
  defp handle_downstream_data(bin, :busy, data(db_pid: db_pid) = data) do
    Logger.debug("ClientHandler: Forward query to db #{inspect(bin)} #{inspect(db_pid)}")
    :ok = forward_to_db(bin, data)

    :keep_state_and_data
  end

  @spec handle_actions(t()) :: [{:timeout, non_neg_integer, atom}]
  defp handle_actions(data(heartbeat_interval: heart, idle_timeout: idle)) do
    heartbeat =
      if heart > 0,
        do: [{:timeout, heart, :heartbeat_check}],
        else: []

    if idle > 0, do: [{:timeout, idle, :idle_terminate} | heartbeat], else: heartbeat
  end

  @compile {:inline, forward_to_db: 2}

  @spec forward_to_db(binary(), t()) :: :ok | {:error, term()}
  defp forward_to_db(bin, data(db_pid: {_, _, db_sock})) do
    case HandlerHelpers.sock_send(db_sock, bin) do
      :ok ->
        :ok

      {:error, error} ->
        Logger.error("ClientHandler: error while sending query: #{inspect(error)}")

        raise Errors.QuerySendError, error: error
    end
  end

  defp net_stats(data) do
    data(id: id, sock: sock, local: local, stats: stats) = data

    {_, stats} =
      if is_nil(id) or local,
        do: {nil, stats},
        else: Telem.network_usage(:client, sock, id, stats)

    data(data, stats: stats)
  end
end
