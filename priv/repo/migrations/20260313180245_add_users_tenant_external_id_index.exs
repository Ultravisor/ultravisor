# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.AddUsersTenantExternalIdIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:users, [:tenant_external_id], prefix: "_ultravisor")
  end
end
