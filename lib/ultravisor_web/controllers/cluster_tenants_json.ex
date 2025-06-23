# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.ClusterTenantsJSON do
  alias Ultravisor.Tenants.ClusterTenants

  @doc """
  Renders a list of cluster_tenants.
  """
  def index(%{cluster_tenants: cluster_tenants}) do
    %{data: Enum.map(cluster_tenants, &data/1)}
  end

  @doc """
  Renders a single cluster_tenants.
  """
  def show(%{cluster_tenants: cluster_tenants}) do
    %{data: data(cluster_tenants)}
  end

  def data(%ClusterTenants{} = cluster_tenants) do
    %{
      id: cluster_tenants.id,
      active: cluster_tenants.active,
      cluster_alias: cluster_tenants.cluster_alias,
      tenant_external_id: cluster_tenants.tenant_external_id,
      inserted_at: cluster_tenants.inserted_at,
      updated_at: cluster_tenants.updated_at
    }
  end
end
