# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.AddDefaultPoolStrategy do
  use Ecto.Migration

  def change do
    alter table("tenants", prefix: "_ultravisor") do
      add(:default_pool_strategy, :string, null: false, default: "fifo")
    end

    create(
      constraint(
        "tenants",
        :default_pool_strategy_values,
        check: "default_pool_strategy IN ('fifo', 'lifo')",
        prefix: "_ultravisor"
      )
    )
  end
end
