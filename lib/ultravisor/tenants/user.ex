# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Tenants.User do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "_ultravisor"

  schema "users" do
    field(:db_user_alias, :string)
    field(:db_user, :string)
    field(:db_password, Ultravisor.Encrypted.Binary, source: :db_pass_encrypted)
    field(:is_manager, :boolean, default: false)
    field(:mode_type, Ecto.Enum, values: [:transaction, :session])
    field(:pool_size, :integer)
    field(:pool_checkout_timeout, :integer, default: 60_000)
    field(:max_clients, :integer)

    belongs_to(:tenant, Ultravisor.Tenants.Tenant,
      foreign_key: :tenant_external_id,
      type: :string
    )

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :db_user_alias,
      :db_user,
      :db_password,
      :pool_size,
      :mode_type,
      :is_manager,
      :pool_checkout_timeout,
      :max_clients
    ])
    |> fill_from_if_empty(:db_user_alias, :db_user)
    |> validate_required([
      :db_user_alias,
      :db_user,
      :db_password,
      :pool_size,
      :mode_type
    ])
  end

  defp fill_from_if_empty(changeset, target, source) do
    if Ecto.Changeset.get_change(changeset, target) do
      changeset
    else
      value = Ecto.Changeset.get_field(changeset, source)
      Ecto.Changeset.put_change(changeset, target, value)
    end
  end
end
