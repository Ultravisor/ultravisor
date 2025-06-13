# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

defmodule Supavisor.Repo.Migrations.CreateClusters do
  use Ecto.Migration

  def change do
    create table("clusters", primary_key: false, prefix: "_supavisor") do
      add(:id, :binary_id, primary_key: true)
      add(:active, :boolean, default: false, null: false)
      add(:alias, :string, null: false)

      timestamps()
    end

    create(index(:clusters, [:alias], unique: true, prefix: "_supavisor"))
  end
end
