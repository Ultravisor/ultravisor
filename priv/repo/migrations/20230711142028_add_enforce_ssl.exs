# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

defmodule Supavisor.Repo.Migrations.AddEnforceSsl do
  use Ecto.Migration

  def up do
    alter table("tenants", prefix: "_supavisor") do
      add(:enforce_ssl, :boolean, null: false, default: false)
    end
  end

  def down do
    alter table("tenants", prefix: "_supavisor") do
      remove(:enforce_ssl)
    end
  end
end
