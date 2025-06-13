# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.AddTimeoutToUsers do
  use Ecto.Migration

  def up do
    alter table("users", prefix: "_ultravisor") do
      add(:pool_checkout_timeout, :integer, default: 60_000, null: false)
    end
  end

  def down do
    alter table("users", prefix: "_ultravisor") do
      remove(:pool_checkout_timeout)
    end
  end
end
