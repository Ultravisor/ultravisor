# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.MetricsCleaner do
  @moduledoc false

  use GenServer

  require Logger

  @interval :timer.minutes(30)
  @name __MODULE__

  def start_link(args),
    do: GenServer.start_link(__MODULE__, args, name: @name)

  def clean do
    GenServer.cast(@name, :clean)
  end

  def init(_args) do
    Logger.info("Starting MetricsCleaner")

    :telemetry.attach(
      {__MODULE__, :report},
      [:ultravisor, :metrics_cleaner, :stop],
      &__MODULE__.__report_long_cleanups__/4,
      []
    )

    {:ok, %{check_ref: check()}}
  end

  @doc false
  def __report_long_cleanups__(_event_name, %{duration: duration}, _metadata, _config) do
    exec_time = :erlang.convert_time_unit(duration, :native, :millisecond)

    if exec_time > :timer.seconds(5),
      do: Logger.warning("Metrics check took: #{exec_time} ms")
  end

  def handle_continue(:clean, state) do
    Process.cancel_timer(state.check_ref)

    :telemetry.span([:ultravisor, :metrics_cleaner], %{}, fn ->
      count = loop_and_cleanup_metrics_table()
      {[], %{orphaned_metrics: count}, %{}}
    end)

    {:noreply, %{state | check_ref: check()}}
  end

  def handle_cast(:clean, state) do
    {:noreply, state, {:continue, :clean}}
  end

  def handle_info(:check, state) do
    {:noreply, state, {:continue, :clean}}
  end

  def handle_info(msg, state) do
    Logger.error("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp check, do: Process.send_after(self(), :check, @interval)

  defp loop_and_cleanup_metrics_table do
    {_, tids} = Peep.Persistent.storage(Ultravisor.Monitoring.PromEx.Metrics)

    tids
    |> to_list()
    |> Enum.sum_by(&clean_table/1)
  end

  defp to_list(map) when is_map(map), do: Map.values(map)
  defp to_list(other), do: List.wrap(other)

  @tenant_registry_table :syn_registry_by_name_tenants

  defp clean_table(tid) do
    func =
      fn elem, acc ->
        with {{_,
               %{
                 type: _type,
                 mode: _mode,
                 user: _user,
                 tenant: _tenant,
                 db_name: _db,
                 search_path: _search_path
               } = map} = key, _} <- elem,
             id = Ultravisor.map_to_conn_id(map),
             [] <- :ets.lookup(@tenant_registry_table, id) do
          Logger.warning("Found orphaned metric: #{inspect(key)}")
          :ets.delete(tid, key)

          acc + 1
        else
          _ -> acc
        end
      end

    :ets.foldl(func, 0, tid)
  end
end
