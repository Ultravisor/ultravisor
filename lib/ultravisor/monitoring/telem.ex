# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Monitoring.Telem do
  @moduledoc false

  require Logger

  import Ultravisor, only: [conn_id: 0, conn_id: 1]

  @type net_stats() :: {non_neg_integer(), non_neg_integer()}

  @spec network_usage(:client | :db, Ultravisor.sock(), Ultravisor.id(), net_stats()) ::
          {:ok | :error, net_stats()}
  def network_usage(type, {mod, socket}, id, {prev_recv, prev_send} = stats) do
    mod = if mod == :ssl, do: :ssl, else: :inet

    case mod.getstat(socket, [:recv_oct, :send_oct]) do
      {:ok, [{:recv_oct, recv_oct}, {:send_oct, send_oct}]} ->
        stats = %{
          send_oct: send_oct - prev_send,
          recv_oct: recv_oct - prev_recv
        }

        conn_id(
          type: ptype,
          tenant: tenant,
          user: user,
          mode: mode,
          db_name: db_name,
          search_path: search_path
        ) = id

        :telemetry.execute(
          [:ultravisor, type, :network, :stat],
          stats,
          %{
            tenant: tenant,
            user: user,
            mode: mode,
            type: ptype,
            db_name: db_name,
            search_path: search_path
          }
        )

        {:ok, {send_oct, recv_oct}}

      {:error, reason} ->
        Logger.error("Failed to get socket stats: #{inspect(reason)}")
        {:error, stats}
    end
  end

  @spec pool_checkout_time(integer(), Ultravisor.id(), :local | :remote) :: :ok | nil
  def pool_checkout_time(time, conn_id() = id, same_box) do
    :telemetry.execute(
      [:ultravisor, :pool, :checkout, :stop, same_box],
      %{duration: time},
      Ultravisor.conn_id_to_map(id)
    )
  end

  @spec client_query_time(integer(), Ultravisor.id()) :: :ok | nil
  def client_query_time(start, conn_id() = id) do
    :telemetry.execute(
      [:ultravisor, :client, :query, :stop],
      %{duration: System.monotonic_time() - start},
      Ultravisor.conn_id_to_map(id)
    )
  end

  @spec client_connection_time(integer(), Ultravisor.id()) :: :ok | nil
  def client_connection_time(start, conn_id() = id) do
    :telemetry.execute(
      [:ultravisor, :client, :connection, :stop],
      %{duration: System.monotonic_time() - start},
      Ultravisor.conn_id_to_map(id)
    )
  end

  @spec client_join(:ok | :fail, Ultravisor.id() | any()) :: :ok | nil
  def client_join(status, conn_id() = id) do
    :telemetry.execute(
      [:ultravisor, :client, :joins, status],
      %{},
      Ultravisor.conn_id_to_map(id)
    )
  end

  def client_join(_status, id) do
    Logger.warning("client_join is called with a mismatched id: #{inspect(id)}")
  end

  @spec handler_action(
          :client_handler | :db_handler,
          :started | :stopped | :db_connection,
          Ultravisor.id()
        ) :: :ok | nil
  def handler_action(handler, action, conn_id() = id) do
    :telemetry.execute(
      [:ultravisor, handler, action, :all],
      %{},
      Ultravisor.conn_id_to_map(id)
    )
  end

  def handler_action(handler, action, id) do
    Logger.warning(
      "handler_action is called with a mismatched #{inspect(handler)} #{inspect(action)} #{inspect(id)}"
    )
  end

  def handle_system_monitor([:erlang, :sys_mon, kind], measurements, meta, _opts) do
    Logger.warning(
      %{
        sys_mon: %{
          kind: kind,
          info: measurements,
          meta: meta
        }
      },
      report_cb: &__MODULE__.__sys_mon_report__/1
    )
  end

  def handle_system_monitor([:erlang, :sys_mon, :long_schedule, _], measurements, meta, _opts) do
    Logger.warning(
      %{
        sys_mon: %{
          kind: :long_schedule,
          info: measurements,
          meta: meta
        }
      },
      report_cb: &__MODULE__.__sys_mon_report__/1
    )
  end

  def __sys_mon_report__(%{sys_mon: event}) do
    %{kind: kind, info: info, meta: meta} = event

    {"ErlSysMon message: ~p ~p ~p", [kind, info, meta]}
  end
end
