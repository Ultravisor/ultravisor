# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Monitoring.PromEx do
  @moduledoc """
  This module configures the PromEx application for Ultravisor. It defines
  the plugins used for collecting metrics, including built-in plugins and custom ones,
  and provides a function to remove remote metrics associated with a specific tenant.
  """

  use PromEx, otp_app: :ultravisor
  require Logger

  alias PromEx.Plugins
  alias Ultravisor.PromEx.Plugins.{OsMon, Tenant}

  defmodule Store do
    @moduledoc """
    Storage module for PromEx that provide additional functionality of using
    global tags (extracted from Logger global metadata). It also disables
    scraping using `PromEx.scrape/1` function as it should not be used directly.
    We expose scraping via `Ultravisor.Monitoring.PromEx.get_metrics/0` function.
    """

    @behaviour PromEx.Storage

    @impl true
    def scrape(name) do
      name
      |> Peep.get_all_metrics()
      |> Peep.Prometheus.export()
    end

    @impl true
    def child_spec(name, metrics) do
      global_tags = :logger.get_primary_config().metadata
      global_tags_keys = Map.keys(global_tags)

      Peep.child_spec(
        name: name,
        metrics: Enum.map(metrics, &extend_tags(&1, global_tags_keys)),
        global_tags: global_tags,
        storage: :striped
      )
    end

    defp extend_tags(%{tags: tags} = metric, global_tags) do
      %{metric | tags: tags ++ global_tags}
    end
  end

  @impl true
  def plugins do
    poll_rate = Application.fetch_env!(:ultravisor, :prom_poll_rate)

    [
      # PromEx built in plugins
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: UltravisorWeb.Router, endpoint: UltravisorWeb.Endpoint},
      Plugins.Ecto,

      # Custom PromEx metrics plugins
      {OsMon, poll_rate: poll_rate},
      {Tenant, poll_rate: poll_rate}
    ]
  end

  @spec get_metrics() :: iodata()
  def get_metrics do
    PromEx.get_metrics(__MODULE__)
  end
end
