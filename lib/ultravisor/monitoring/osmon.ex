# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.PromEx.Plugins.OsMon do
  @moduledoc """
  Polls os_mon metrics.
  """

  use PromEx.Plugin
  require Logger

  @event_ram_usage [:prom_ex, :plugin, :osmon, :ram_usage]
  @event_cpu_util [:prom_ex, :plugin, :osmon, :cpu_util]
  @event_cpu_la [:prom_ex, :plugin, :osmon, :cpu_avg1]
  @prefix [:ultravisor, :prom_ex]

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate)

    [
      metrics(poll_rate)
    ]
  end

  defp metrics(poll_rate) do
    Polling.build(
      :ultravisor_osmon_events,
      poll_rate,
      {__MODULE__, :execute_metrics, []},
      [
        last_value(
          @prefix ++ [:osmon, :ram_usage],
          event_name: @event_ram_usage,
          description: "The total percentage usage of operative memory.",
          measurement: :ram
        ),
        last_value(
          @prefix ++ [:osmon, :cpu_util],
          event_name: @event_cpu_util,
          description:
            "The sum of the percentage shares of the CPU cycles spent in all busy processor states in average on all CPUs.",
          measurement: :cpu
        ),
        last_value(
          @prefix ++ [:osmon, :cpu_avg1],
          event_name: @event_cpu_la,
          description: "The average system load in the last minute.",
          measurement: :avg1
        ),
        last_value(
          @prefix ++ [:osmon, :cpu_avg5],
          event_name: @event_cpu_la,
          description: "The average system load in the last five minutes.",
          measurement: :avg5
        ),
        last_value(
          @prefix ++ [:osmon, :cpu_avg15],
          event_name: @event_cpu_la,
          description: "The average system load in the last 15 minutes.",
          measurement: :avg15
        )
      ]
    )
  end

  def execute_metrics do
    execute_metrics(@event_ram_usage, %{ram: ram_usage()})
    execute_metrics(@event_cpu_util, %{cpu: cpu_util()})
    execute_metrics(@event_cpu_la, cpu_la())
  end

  def execute_metrics(event, metrics) do
    :telemetry.execute(event, metrics, %{})
  end

  @spec ram_usage() :: float()
  defp ram_usage do
    mem = :memsup.get_system_memory_data()
    100 - mem[:free_memory] / mem[:total_memory] * 100
  end

  @spec cpu_la() :: %{avg1: float(), avg5: float(), avg15: float()}
  defp cpu_la do
    %{
      avg1: :cpu_sup.avg1() / 256,
      avg5: :cpu_sup.avg5() / 256,
      avg15: :cpu_sup.avg15() / 256
    }
  end

  @spec cpu_util() :: float() | {:error, term()}
  defp cpu_util do
    :cpu_sup.util()
  end
end
