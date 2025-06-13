# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.MetricsCleanerTest do
  use ExUnit.Case, async: false

  alias Ultravisor.PromEx.Plugins.Tenant, as: Metrics

  @subject Ultravisor.MetricsCleaner

  doctest @subject

  setup ctx do
    :telemetry.attach(ctx, [:ultravisor, :metrics_cleaner, :stop], &__MODULE__.handler/4, %{
      parent: self()
    })

    :ok
  end

  def handler(_, measurements, _, %{parent: pid}) do
    send(pid, {:metrics, measurements})
  end

  test "metrics for unknown tenant are removed" do
    :ok =
      Metrics.emit_telemetry_for_tenant(
        {{{:single, "non-existent"}, "foo", :transaction, "bar", nil}, 2137}
      )

    metrics = Ultravisor.Monitoring.PromEx.get_metrics()

    assert IO.iodata_to_binary(metrics) =~ ~r/non-existent/

    @subject.clean()

    assert_receive {:metrics, _}

    metrics = Ultravisor.Monitoring.PromEx.get_metrics()

    refute IO.iodata_to_binary(metrics) =~ ~r/non-existent/
  end
end
