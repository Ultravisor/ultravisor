# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

defmodule Supavisor.Repo.Migrations.AddUserMaxClients do
  use Ecto.Migration

  def change do
    alter table("users", prefix: "_supavisor") do
      add(:max_clients, :integer, null: true)
    end
  end
end
