# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.AddEnforceSsl do
  use Ecto.Migration

  def up do
    alter table("tenants", prefix: "_ultravisor") do
      add(:enforce_ssl, :boolean, null: false, default: false)
    end
  end

  def down do
    alter table("tenants", prefix: "_ultravisor") do
      remove(:enforce_ssl)
    end
  end
end
