# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.AddTenantIpVersion do
  use Ecto.Migration

  def up do
    alter table("tenants", prefix: "_ultravisor") do
      add(:ip_version, :string, null: false, default: "auto")
    end

    create(
      constraint(
        "tenants",
        :ip_version_values,
        check: "ip_version IN ('auto', 'v4', 'v6')",
        prefix: "_ultravisor"
      )
    )
  end

  def down do
    alter table("tenants", prefix: "_ultravisor") do
      remove(:ip_version)
    end

    drop(constraint("tenants", "ip_version_values"))
  end
end
