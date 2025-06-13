# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.PromEx.Plugins.Tenant do
  @moduledoc "This module defines the PromEx plugin for Ultravisor tenants."

  use PromEx.Plugin
  require Logger

  @tags [:tenant, :user, :mode, :type, :db_name, :search_path]

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    [
      concurrent_connections(poll_rate),
      concurrent_proxy_connections(poll_rate),
      concurrent_tenants(poll_rate)
    ]
  end

  @impl true
  def event_metrics(_opts) do
    [
      system_metrics(),
      client_metrics(),
      db_metrics()
    ]
  end

  defmodule Buckets do
    @moduledoc false
    use Peep.Buckets.Custom,
      buckets: [1, 5, 10, 100, 1_000, 5_000, 10_000]
  end

  defp system_metrics do
    Event.build(
      :ultravisor_metrics_cleaner_metrics,
      [
        counter(
          [:ultravisor, :metrics_cleaner, :orphaned_metrics],
          event_name: [:ultravisor, :metrics, :orphaned],
          description: "Amount of orphaned metrics that were cleaned up"
        )
      ]
    )
  end

  defp client_metrics do
    Event.build(
      :ultravisor_tenant_client_event_metrics,
      [
        distribution(
          [:ultravisor, :pool, :checkout, :duration, :local, :us],
          event_name: [:ultravisor, :pool, :checkout, :stop, :local],
          measurement: :duration,
          description: "Duration of the checkout local process in the tenant db pool.",
          tags: @tags,
          unit: {:native, :microsecond},
          reporter_options: [
            peep_bucket_calculator: Buckets
          ]
        ),
        distribution(
          [:ultravisor, :pool, :checkout, :duration, :remote, :us],
          event_name: [:ultravisor, :pool, :checkout, :stop, :remote],
          measurement: :duration,
          description: "Duration of the checkout remote process in the tenant db pool.",
          tags: @tags,
          unit: {:native, :microsecond},
          reporter_options: [
            peep_bucket_calculator: Buckets
          ]
        ),
        distribution(
          [:ultravisor, :client, :query, :duration],
          event_name: [:ultravisor, :client, :query, :stop],
          measurement: :duration,
          description: "Duration of processing the query.",
          tags: @tags,
          unit: {:native, :millisecond},
          reporter_options: [
            peep_bucket_calculator: Buckets
          ]
        ),
        distribution(
          [:ultravisor, :client, :connection, :duration],
          event_name: [:ultravisor, :client, :connection, :stop],
          measurement: :duration,
          description: "Duration from the TCP connection to sending greetings to clients.",
          tags: @tags,
          unit: {:native, :millisecond},
          reporter_options: [
            peep_bucket_calculator: Buckets
          ]
        ),
        sum(
          [:ultravisor, :client, :network, :recv],
          event_name: [:ultravisor, :client, :network, :stat],
          measurement: :recv_oct,
          description: "The total number of bytes received by clients.",
          tags: @tags
        ),
        sum(
          [:ultravisor, :client, :network, :send],
          event_name: [:ultravisor, :client, :network, :stat],
          measurement: :send_oct,
          description: "The total number of bytes sent by clients.",
          tags: @tags
        ),
        counter(
          [:ultravisor, :client, :queries, :count],
          event_name: [:ultravisor, :client, :query, :stop],
          description: "The total number of queries received by clients.",
          tags: @tags
        ),
        counter(
          [:ultravisor, :client, :joins, :ok],
          event_name: [:ultravisor, :client, :joins, :ok],
          description: "The total number of successful joins.",
          tags: @tags
        ),
        counter(
          [:ultravisor, :client, :joins, :fail],
          event_name: [:ultravisor, :client, :joins, :fail],
          description: "The total number of failed joins.",
          tags: @tags
        ),
        counter(
          [:ultravisor, :client_handler, :started, :count],
          event_name: [:ultravisor, :client_handler, :started, :all],
          description: "The total number of created client_handler.",
          tags: @tags
        ),
        counter(
          [:ultravisor, :client_handler, :stopped, :count],
          event_name: [:ultravisor, :client_handler, :stopped, :all],
          description: "The total number of stopped client_handler.",
          tags: @tags
        )
      ]
    )
  end

  defp db_metrics do
    Event.build(
      :ultravisor_tenant_db_event_metrics,
      [
        sum(
          [:ultravisor, :db, :network, :recv],
          event_name: [:ultravisor, :db, :network, :stat],
          measurement: :recv_oct,
          description: "The total number of bytes received by db process",
          tags: @tags
        ),
        sum(
          [:ultravisor, :db, :network, :send],
          event_name: [:ultravisor, :db, :network, :stat],
          measurement: :send_oct,
          description: "The total number of bytes sent by db process",
          tags: @tags
        ),
        counter(
          [:ultravisor, :db_handler, :started, :count],
          event_name: [:ultravisor, :db_handler, :started, :all],
          description: "The total number of created db_handler.",
          tags: @tags
        ),
        counter(
          [:ultravisor, :db_handler, :stopped, :count],
          event_name: [:ultravisor, :db_handler, :stopped, :all],
          description: "The total number of stopped db_handler.",
          tags: @tags
        ),
        counter(
          [:ultravisor, :db_handler, :db_connection, :count],
          event_name: [:ultravisor, :db_handler, :db_connection, :all],
          description: "The total number of database connections by db_handler.",
          tags: @tags
        )
      ]
    )
  end

  defp concurrent_connections(poll_rate) do
    Polling.build(
      :ultravisor_concurrent_connections,
      poll_rate,
      {__MODULE__, :execute_tenant_metrics, []},
      [
        last_value(
          [:ultravisor, :connections, :active],
          event_name: [:ultravisor, :connections],
          description: "The total count of active clients for a tenant.",
          measurement: :active,
          tags: @tags
        )
      ]
    )
  end

  def execute_tenant_metrics do
    Registry.select(Ultravisor.Registry.TenantClients, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.frequencies()
    |> Enum.each(&emit_telemetry_for_tenant/1)
  end

  @spec emit_telemetry_for_tenant({Ultravisor.id(), non_neg_integer()}) :: :ok
  def emit_telemetry_for_tenant({id, count}) do
    :telemetry.execute(
      [:ultravisor, :connections],
      %{active: count},
      Ultravisor.conn_id_to_map(id)
    )
  end

  defp concurrent_proxy_connections(poll_rate) do
    Polling.build(
      :ultravisor_concurrent_proxy_connections,
      poll_rate,
      {__MODULE__, :execute_tenant_proxy_metrics, []},
      [
        last_value(
          [:ultravisor, :proxy, :connections, :active],
          event_name: [:ultravisor, :proxy, :connections],
          description: "The total count of active proxy clients for a tenant.",
          measurement: :active,
          tags: @tags
        )
      ]
    )
  end

  def execute_tenant_proxy_metrics do
    Registry.select(Ultravisor.Registry.TenantProxyClients, [{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.frequencies()
    |> Enum.each(&emit_proxy_telemetry_for_tenant/1)
  end

  @spec emit_proxy_telemetry_for_tenant({Ultravisor.id(), non_neg_integer()}) :: :ok
  def emit_proxy_telemetry_for_tenant({id, count}) do
    :telemetry.execute(
      [:ultravisor, :proxy, :connections],
      %{active: count},
      Ultravisor.conn_id_to_map(id)
    )
  end

  defp concurrent_tenants(poll_rate) do
    Polling.build(
      :ultravisor_concurrent_tenants,
      poll_rate,
      {__MODULE__, :execute_conn_tenants_metrics, []},
      [
        last_value(
          [:ultravisor, :tenants, :active],
          event_name: [:ultravisor, :tenants],
          description: "The total count of active tenants.",
          measurement: :active
        )
      ]
    )
  end

  def execute_conn_tenants_metrics do
    num =
      Registry.select(Ultravisor.Registry.TenantSups, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> Enum.uniq()
      |> Enum.count()

    :telemetry.execute(
      [:ultravisor, :tenants],
      %{active: num}
    )
  end
end
