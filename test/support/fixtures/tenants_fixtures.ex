# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.TenantsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ultravisor.Tenants` context.
  """

  @doc """
  Generate a tenant.
  """
  def tenant_fixture(attrs \\ %{}) do
    {:ok, tenant} =
      attrs
      |> Enum.into(%{
        db_database: "some db_database",
        db_host: "some db_host",
        db_port: 42,
        external_id: "dev_tenant",
        default_parameter_status: %{"server_version" => "15.0"},
        require_user: true,
        users: [
          %{
            "db_user" => "postgres",
            "db_password" => "postgres",
            "pool_size" => 3,
            "mode_type" => "transaction"
          }
        ]
      })
      |> Ultravisor.Tenants.create_tenant()

    tenant
  end
end
