# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

defmodule Supavisor.Repo.Migrations.AddAwsZone do
  use Ecto.Migration

  def change do
    alter table("tenants", prefix: "_supavisor") do
      add(:availability_zone, :string)
    end
  end
end
