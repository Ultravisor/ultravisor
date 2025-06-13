# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

defmodule Supavisor.Repo.Migrations.AddHeartbeatInterval do
  use Ecto.Migration

  def change do
    alter table("tenants", prefix: "_supavisor") do
      add(:client_heartbeat_interval, :integer, null: false, default: 60)
    end
  end
end
