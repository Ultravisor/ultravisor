# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  alias Ultravisor.Monitoring.PromEx

  @impl true
  def start(_type, _args) do
    primary_config = :logger.get_primary_config()

    {:ok, host} = :inet.gethostname()

    global_metadata =
      Application.get_env(:ultravisor, :metadata, %{})
      |> Map.merge(%{
        hostname: to_string(host)
      })

    :ok =
      :logger.set_primary_config(
        :metadata,
        Map.merge(primary_config.metadata, global_metadata)
      )

    :ok = Logger.add_handlers(:ultravisor)

    proxy_ports = [
      {:pg_proxy_transaction, Application.get_env(:ultravisor, :proxy_port_transaction),
       :transaction, Ultravisor.ClientHandler},
      {:pg_proxy_session, Application.get_env(:ultravisor, :proxy_port_session), :session,
       Ultravisor.ClientHandler},
      {:pg_proxy, Application.get_env(:ultravisor, :proxy_port), :proxy, Ultravisor.ClientHandler}
    ]

    for {key, port, mode, handler} <- proxy_ports do
      case :ranch.start_listener(
             key,
             :ranch_tcp,
             %{
               max_connections: String.to_integer(System.get_env("MAX_CONNECTIONS") || "75000"),
               num_acceptors: String.to_integer(System.get_env("NUM_ACCEPTORS") || "100"),
               socket_opts: [port: port, keepalive: true]
             },
             handler,
             %{mode: mode}
           ) do
        {:ok, _pid} ->
          Logger.notice("Proxy started #{mode} on port #{port}")

        error ->
          Logger.error("Proxy on #{port} not started because of #{inspect(error)}")
      end
    end

    :syn.set_event_handler(Ultravisor.SynHandler)
    :syn.add_node_to_scopes([:tenants, :availability_zone])

    :syn.join(:availability_zone, Application.get_env(:ultravisor, :availability_zone), self(),
      node: node()
    )

    children =
      Enum.concat([
        registries(),
        cache(),
        [
          Ultravisor.Repo,
          {Cluster.Supervisor, [topologies(), [name: Ultravisor.ClusterSupervisor]]}
        ],
        metrics(),
        [
          # Start the Telemetry supervisor
          UltravisorWeb.Telemetry,
          # Start the PubSub system
          {Phoenix.PubSub, name: Ultravisor.PubSub},
          {
            PartitionSupervisor,
            child_spec: DynamicSupervisor,
            strategy: :one_for_one,
            name: Ultravisor.DynamicSupervisor
          },
          Ultravisor.Vault,

          # Start the Endpoint (http/https)
          UltravisorWeb.Endpoint
        ]
      ])

    :telemetry.attach_many(
      :ultravisor_sys_mon,
      [
        [:erlang, :sys_mon, :long_gc],
        [:erlang, :sys_mon, :large_heap],
        [:erlang, :sys_mon, :long_schedule, :process],
        [:erlang, :sys_mon, :long_schedule, :port],
        [:erlang, :sys_mon, :long_message_queue],
        [:erlang, :sys_mon, :busy_port],
        [:erlang, :sys_mon, :busy_dist_port]
      ],
      &Ultravisor.Monitoring.Telem.handle_system_monitor/4,
      []
    )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ultravisor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp registries do
    [
      {Registry, keys: :unique, name: Ultravisor.Registry.Tenants},
      {Registry, keys: :unique, name: Ultravisor.Registry.ManagerTables},
      {Registry, keys: :unique, name: Ultravisor.Registry.PoolPids},
      {Registry, keys: :duplicate, name: Ultravisor.Registry.TenantSups},
      {Registry,
       keys: :duplicate,
       name: Ultravisor.Registry.TenantClients,
       partitions: System.schedulers_online()},
      {Registry,
       keys: :duplicate,
       name: Ultravisor.Registry.TenantProxyClients,
       partitions: System.schedulers_online()}
    ]
  end

  defp metrics do
    if Application.get_env(:ultravisor, :metrics_enabled, true) do
      [PromEx, Ultravisor.MetricsCleaner]
    else
      Logger.warning("Metrics gathering is disabled")
      []
    end
  end

  defp topologies do
    case Application.fetch_env(:ultravisor, :cluster_channel) do
      {:ok, channel} when is_binary(channel) and channel != "" ->
        [
          postgres: [
            strategy: LibclusterPostgres.Strategy,
            config:
              Ultravisor.Repo.config() ++
                [
                  channel_name: channel
                ]
          ]
        ]

      _ ->
        []
    end
  end

  # start Cachex only if the node uses names, this is necessary for test setup
  defp cache do
    if node() != :nonode@nohost do
      [{Cachex, name: Ultravisor.Cache}]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    UltravisorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
