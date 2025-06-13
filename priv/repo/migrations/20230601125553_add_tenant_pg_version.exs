# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.AddTenantDefaultPS do
  use Ecto.Migration

  def up do
    alter table("tenants", prefix: "_ultravisor") do
      add(:default_parameter_status, :map, null: false)
    end
  end

  def down do
    alter table("tenants", prefix: "_ultravisor") do
      remove(:default_parameter_status)
    end
  end
end
