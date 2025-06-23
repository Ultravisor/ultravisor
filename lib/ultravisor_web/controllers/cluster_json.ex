# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.ClusterJSON do
  alias Ultravisor.Tenants.Cluster

  @doc """
  Renders a list of clusters.
  """
  def index(%{clusters: clusters}) do
    %{data: Enum.map(clusters, &data/1)}
  end

  @doc """
  Renders a single cluster.
  """
  def show(%{cluster: cluster}) do
    %{data: data(cluster)}
  end

  defp data(%Cluster{} = cluster) do
    %{
      id: cluster.id,
      alias: cluster.alias,
      active: cluster.active,
      inserted_at: cluster.inserted_at,
      cluster_tenants:
        Enum.map(
          cluster.cluster_tenants,
          &UltravisorWeb.ClusterTenantsJSON.data/1
        )
    }
  end
end
