# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.ClusterController do
  use UltravisorWeb, :controller

  require Logger

  alias Ultravisor.Repo
  alias Ultravisor.Tenants
  alias Ultravisor.Tenants.Cluster, as: ClusterModel

  action_fallback(UltravisorWeb.FallbackController)

  def create(conn, %{"cluster" => params}) do
    with {:ok, %ClusterModel{} = cluster} <- Tenants.create_cluster(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.tenant_path(conn, :show, cluster))
      |> render(:show, cluster: cluster)
    end
  end

  def show(conn, %{"alias" => id}) do
    id
    |> Tenants.get_cluster_by_alias()
    |> case do
      %ClusterModel{} = cluster ->
        render(conn, "show.json", cluster: cluster)

      nil ->
        conn
        |> put_status(404)
        |> render("not_found.json", cluster: nil)
    end
  end

  def update(conn, %{"alias" => id, "cluster" => params}) do
    cluster_tenants =
      Enum.map(params["cluster_tenants"], fn e ->
        Map.put(e, "cluster_alias", id)
      end)

    params = %{params | "cluster_tenants" => cluster_tenants}

    case Tenants.get_cluster_by_alias(id) do
      nil ->
        create(conn, %{"cluster" => Map.put(params, "alias", id)})

      cluster ->
        cluster = Repo.preload(cluster, :cluster_tenants)

        with {:ok, %ClusterModel{} = cluster} <-
               Tenants.update_cluster(cluster, params) do
          result = Ultravisor.terminate_global("cluster.#{cluster.alias}")
          Logger.warning("Stop #{cluster.alias}: #{inspect(result)}")
          render(conn, "show.json", cluster: cluster)
        end
    end
  end

  def delete(conn, %{"alias" => id}) do
    code = if Tenants.delete_cluster_by_alias(id), do: 204, else: 404

    send_resp(conn, code, "")
  end
end
