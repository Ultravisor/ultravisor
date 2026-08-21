# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.ApiSpecTest do
  use ExUnit.Case, async: true

  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.SecurityScheme
  alias OpenApiSpex.Server

  @subject UltravisorWeb.ApiSpec

  test "builds the OpenAPI specification from the endpoint and router" do
    spec = @subject.spec()

    assert %OpenApi{} = spec
    assert spec.info.title == to_string(Application.spec(:ultravisor, :description))
    assert spec.info.version == to_string(Application.spec(:ultravisor, :vsn))
    assert [%Server{}] = spec.servers

    assert [%{"authorization" => [%SecurityScheme{type: "http", scheme: "bearer"}]}] =
             spec.security

    assert Enum.sort(Map.keys(spec.paths)) == [
             "/api/health",
             "/api/tenants/{external_id}",
             "/api/tenants/{external_id}/terminate"
           ]

    assert %{
             get: %OpenApiSpex.Operation{},
             put: %OpenApiSpex.Operation{},
             delete: %OpenApiSpex.Operation{}
           } = spec.paths["/api/tenants/{external_id}"]

    assert %{get: %OpenApiSpex.Operation{}} =
             spec.paths["/api/tenants/{external_id}/terminate"]

    assert %{get: %OpenApiSpex.Operation{}} = spec.paths["/api/health"]
  end
end
