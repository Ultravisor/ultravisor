# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.CreateClusterTenants do
  use Ecto.Migration

  def change do
    create table("cluster_tenants", primary_key: false, prefix: "_ultravisor") do
      add(:id, :binary_id, primary_key: true)
      add(:type, :string, null: false)
      add(:active, :boolean, default: false, null: false)

      add(
        :cluster_alias,
        references(:clusters,
          on_delete: :delete_all,
          type: :string,
          column: :alias,
          prefix: "_ultravisor"
        )
      )

      add(
        :tenant_external_id,
        references(:tenants, type: :string, column: :external_id, prefix: "_ultravisor")
      )

      timestamps()
    end

    create(
      constraint(
        :cluster_tenants,
        :type,
        check: "type IN ('read', 'write')",
        prefix: "_ultravisor"
      )
    )

    create(
      index(:cluster_tenants, [:tenant_external_id],
        unique: true,
        prefix: "_ultravisor"
      )
    )
  end
end
