# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Tenants.Cluster do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  alias Ultravisor.Tenants.ClusterTenants

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "_ultravisor"

  schema "clusters" do
    field(:active, :boolean, default: false)
    field(:alias, :string)

    has_many(:cluster_tenants, ClusterTenants,
      foreign_key: :cluster_alias,
      references: :alias,
      on_delete: :delete_all,
      on_replace: :delete
    )

    timestamps()
  end

  @doc false
  def changeset(cluster, attrs) do
    cluster
    |> cast(attrs, [:active, :alias])
    |> validate_required([:active, :alias])
    |> unique_constraint([:alias])
    |> cast_assoc(:cluster_tenants, with: &ClusterTenants.changeset/2)
  end
end
