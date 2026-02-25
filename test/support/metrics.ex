defmodule Ultravisor.Support.Metrics do
  import ExUnit.Assertions

  def get(metric_name, tags \\ %{}) do
    assert %{^metric_name => data} = get_all([metric_name], tags)

    data
  end

  def get_all(metric_names, tags \\ %{}) do
    defaults = Map.new(metric_names, &{&1, []})

    measurements =
      Peep.get_all_metrics(Ultravisor.Monitoring.PromEx.Metrics)
      |> Enum.filter(fn {metric, _values} -> metric.name in metric_names end)
      |> Map.new(fn {metric, values} ->
        values =
          Enum.filter(values, fn {labels, _value} ->
            Map.intersect(tags, labels) == tags
          end)

        {metric.name, values}
      end)

    Map.merge(defaults, measurements)
  end
end
