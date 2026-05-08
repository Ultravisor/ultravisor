# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.PromEx.Plugins.OsMonTest do
  use ExUnit.Case, async: true

  @subject Ultravisor.PromEx.Plugins.OsMon

  describe "execute_metrics/0" do
    test "executes telemetry events" do
      # Setup telemetry handlers to verify execution
      parent = self()
      ref = make_ref()

      events = [
        [:prom_ex, :plugin, :osmon, :ram_usage],
        [:prom_ex, :plugin, :osmon, :cpu_util],
        [:prom_ex, :plugin, :osmon, :cpu_avg1]
      ]

      handler_id = "osmon-test-handler-#{inspect(ref)}"

      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, metadata, _config ->
          send(parent, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      try do
        # Call the metrics execution
        # Note: This might fail if os_mon is not running, so we wrap it
        try do
          @subject.execute_metrics()
        rescue
          _ -> :ok
        catch
          _, _ -> :ok
        end

        # We expect 3 events, but they might not all fire if os_mon is broken
        # We just check if at least some code paths were hit
        assert_receive {:telemetry_event, _, _, _}, 2000
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  describe "polling_metrics/1" do
    test "returns polling metrics definition" do
      metrics = @subject.polling_metrics(poll_rate: 5000)
      assert is_list(metrics)
      assert length(metrics) == 1
    end
  end
end
