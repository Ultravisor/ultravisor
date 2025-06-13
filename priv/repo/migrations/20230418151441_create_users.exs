# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false, prefix: "_ultravisor") do
      add(:id, :binary_id, primary_key: true)
      add(:db_user_alias, :string, null: false)
      add(:db_user, :string, null: false)
      add(:db_pass_encrypted, :binary, null: false)
      add(:pool_size, :integer, null: false)
      add(:mode_type, :string, null: false)
      add(:is_manager, :boolean, default: false, null: false)

      add(
        :tenant_external_id,
        references(:tenants, on_delete: :delete_all, type: :string, column: :external_id)
      )

      timestamps()
    end

    create(
      index(:users, [:db_user_alias, :tenant_external_id, :mode_type],
        unique: true,
        prefix: "_ultravisor"
      )
    )
  end
end
