# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.AddTenantAllowList do
  use Ecto.Migration

  def change do
    alter table("tenants", prefix: "_ultravisor") do
      add(:allow_list, {:array, :string}, null: false, default: ["0.0.0.0/0", "::/0"])
    end
  end
end
