# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

defmodule Supavisor.Repo.Migrations.AddClientIdleTimeout do
  use Ecto.Migration

  def change do
    alter table("tenants", prefix: "_supavisor") do
      add(:client_idle_timeout, :integer, null: false, default: 0)
    end
  end
end
