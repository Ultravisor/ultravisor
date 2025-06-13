# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.CreateClusters do
  use Ecto.Migration

  def change do
    create table("clusters", primary_key: false, prefix: "_ultravisor") do
      add(:id, :binary_id, primary_key: true)
      add(:active, :boolean, default: false, null: false)
      add(:alias, :string, null: false)

      timestamps()
    end

    create(index(:clusters, [:alias], unique: true, prefix: "_ultravisor"))
  end
end
