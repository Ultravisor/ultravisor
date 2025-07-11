# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.TenantController do
  use UltravisorWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Ultravisor.{
    Helpers,
    Repo,
    Tenants
  }

  alias Tenants.Tenant, as: TenantModel

  alias UltravisorWeb.OpenApiSchemas.{
    Created,
    Empty,
    NotFound,
    Tenant,
    TenantCreate
  }

  action_fallback(UltravisorWeb.FallbackController)

  @authorization [
    in: :header,
    name: "Authorization",
    schema: %OpenApiSpex.Schema{type: :string},
    required: true,
    example:
      "Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpYXQiOjE2ODAxNjIxNTR9.U9orU6YYqXAtpF8uAiw6MS553tm4XxRzxOhz2IwDhpY"
  ]

  def create(conn, %{"tenant" => tenant_params}) do
    with {:ok, %TenantModel{} = tenant} <- Tenants.create_tenant(tenant_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/tenants/#{tenant}")
      |> render(:show, tenant: tenant)
    end
  end

  operation(:show,
    summary: "Fetch Tenant",
    parameters: [
      external_id: [in: :path, description: "External id", type: :string],
      authorization: @authorization
    ],
    responses: %{
      200 => Tenant.response(),
      404 => NotFound.response()
    }
  )

  def show(conn, %{"external_id" => id}) do
    id
    |> Tenants.get_tenant_by_external_id()
    |> case do
      %TenantModel{} = tenant ->
        render(conn, :show, tenant: tenant)

      nil ->
        {:error, :not_found}
    end
  end

  operation(:update,
    summary: "Create or update tenant",
    parameters: [
      external_id: [in: :path, description: "External id", type: :string],
      authorization: @authorization
    ],
    request_body: TenantCreate.params(),
    responses: %{
      201 => Created.response(Tenant),
      404 => NotFound.response()
    }
  )

  # convert cert to pem format
  def update(conn, %{
        "external_id" => id,
        "tenant" => %{"upstream_tls_ca" => "-----BEGIN" <> _ = upstream_tls_ca} = tenant_params
      }) do
    case Helpers.cert_to_bin(upstream_tls_ca) do
      {:ok, bin} ->
        update(conn, %{
          "external_id" => id,
          "tenant" => %{tenant_params | "upstream_tls_ca" => bin}
        })

      {:error, realson} ->
        conn
        |> put_status(400)
        |> render(:error,
          error: "Invalid 'upstream_tls_ca' certificate, reason: #{inspect(realson)}"
        )
    end
  end

  def update(conn, %{"external_id" => id, "tenant" => params}) do
    cleanup_result = Ultravisor.del_all_cache_dist(id)
    Logger.info("Delete cache dist #{id}: #{inspect(cleanup_result)}")

    cert = Helpers.upstream_cert(params["upstream_tls_ca"])

    if params["upstream_ssl"] && params["upstream_verify"] == "peer" && !cert do
      conn
      |> put_status(400)
      |> render(:error,
        error: "Invalid 'upstream_verify' value, 'peer' is not allowed without certificate"
      )
    else
      case Tenants.get_tenant_by_external_id(id) do
        nil ->
          case Helpers.check_creds_get_ver(params) do
            {:error, reason} ->
              conn
              |> put_status(400)
              |> render(:error, error: reason)

            {:ok, pg_version} ->
              params =
                if pg_version do
                  Map.put(params, "default_parameter_status", %{
                    "server_version" => pg_version
                  })
                else
                  params
                end

              create(conn, %{"tenant" => Map.put(params, "external_id", id)})
          end

        tenant ->
          tenant = Repo.preload(tenant, :users)

          with {:ok, %TenantModel{} = tenant} <-
                 Tenants.update_tenant(tenant, params) do
            result = Ultravisor.terminate_global(tenant.external_id)
            Logger.warning("Stop #{tenant.external_id}: #{inspect(result)}")
            render(conn, :show, tenant: tenant)
          end
      end
    end
  end

  operation(:delete,
    summary: "Delete source",
    parameters: [
      external_id: [in: :path, description: "External id", type: :string],
      authorization: @authorization
    ],
    responses: %{
      204 => Empty.response(),
      404 => NotFound.response()
    }
  )

  def delete(conn, %{"external_id" => id}) do
    code = if Tenants.delete_tenant_by_external_id(id), do: 204, else: 404

    result = Ultravisor.del_all_cache_dist(id)

    Logger.info("Delete cache dist #{id}: #{inspect(result)}")

    send_resp(conn, code, "")
  end

  operation(:terminate,
    summary: "Stop tenant's pools and clear cache",
    parameters: [
      external_id: [in: :path, description: "External id", type: :string],
      authorization: @authorization
    ],
    responses: %{
      204 => Empty.response(),
      404 => NotFound.response()
    }
  )

  def terminate(conn, %{"external_id" => external_id}) do
    Logger.metadata(project: external_id)
    result = Ultravisor.terminate_global(external_id) |> inspect()
    Logger.warning("Terminate #{external_id}: #{result}")

    clean_result = Ultravisor.del_all_cache_dist(external_id)

    Logger.info("Delete cache dist #{external_id}: #{inspect(clean_result)}")

    render(conn, :show_terminate, result: result)
  end

  operation(:health,
    summary: "Health check",
    parameters: [],
    responses: %{
      204 => Empty.response()
    }
  )

  def health(conn, _) do
    send_resp(conn, 204, "")
  end
end
