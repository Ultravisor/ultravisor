# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.ApiSpec do
  @moduledoc false

  alias OpenApiSpex.Info
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Paths
  alias OpenApiSpex.SecurityScheme
  alias OpenApiSpex.Server

  alias UltravisorWeb.Endpoint
  alias UltravisorWeb.Router

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    OpenApiSpex.resolve_schema_modules(%OpenApi{
      servers: [Server.from_endpoint(Endpoint)],
      info: %Info{
        title: to_string(Application.spec(:ultravisor, :description)),
        version: to_string(Application.spec(:ultravisor, :vsn))
      },
      paths: Paths.from_router(Router),
      security: [%{"authorization" => [%SecurityScheme{type: "http", scheme: "bearer"}]}]
    })
  end
end
