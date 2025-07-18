# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Tenants.Tenant do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset
  import Ultravisor.Ecto.Changeset

  alias Ultravisor.Tenants.User

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "_ultravisor"

  @derive {JSON.Encoder, except: [:upstream_tls_ca, :__meta__]}

  schema "tenants" do
    field(:db_host, :string)
    field(:db_port, :integer)
    field(:db_database, :string)
    field(:external_id, :string)
    field(:default_parameter_status, :map)
    field(:ip_version, Ecto.Enum, values: [:v4, :v6, :auto], default: :auto)
    field(:upstream_ssl, :boolean, default: false)
    field(:upstream_verify, Ecto.Enum, values: [:none, :peer])
    field(:upstream_tls_ca, Ultravisor.Ecto.Cert)
    field(:enforce_ssl, :boolean, default: false)
    field(:require_user, :boolean, default: false)
    field(:auth_query, :string)
    field(:default_pool_size, :integer, default: 15)
    field(:sni_hostname, :string)
    field(:default_max_clients, :integer, default: 1000)
    field(:client_idle_timeout, :integer, default: 0)
    field(:client_heartbeat_interval, :integer, default: 60)
    field(:allow_list, {:array, :string}, default: ["0.0.0.0/0", "::/0"])
    field(:availability_zone, :string)

    has_many(:users, User,
      foreign_key: :tenant_external_id,
      references: :external_id,
      on_delete: :delete_all,
      on_replace: :delete
    )

    timestamps()
  end

  @doc false
  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [
      :default_parameter_status,
      :external_id,
      :db_host,
      :db_port,
      :db_database,
      :ip_version,
      :upstream_ssl,
      :upstream_verify,
      :upstream_tls_ca,
      :enforce_ssl,
      :require_user,
      :auth_query,
      :default_pool_size,
      :sni_hostname,
      :default_max_clients,
      :client_idle_timeout,
      :client_heartbeat_interval,
      :allow_list,
      :availability_zone
    ])
    |> with_defaults(upstream_tls_ca: Application.get_env(:ultravisor, :global_upstream_ca))
    |> check_constraint(:upstream_ssl, name: :upstream_constraints, prefix: "_ultravisor")
    |> check_constraint(:upstream_verify, name: :upstream_constraints, prefix: "_ultravisor")
    |> validate_required([
      :default_parameter_status,
      :external_id,
      :db_host,
      :db_port,
      :db_database,
      :require_user,
      :allow_list
    ])
    |> validate_allow_list()
    |> unique_constraint([:external_id])
    |> cast_assoc(:users, with: &User.changeset/2)
  end

  @doc """
  Validates CIDRs passed in allow_list field parse correctly.

  ## Examples

    iex> changeset =
    iex> Ecto.Changeset.change(%Ultravisor.Tenants.Tenant{}, %{allow_list: ["0.0.0.0"]})
    iex> |> Ultravisor.Tenants.Tenant.validate_allow_list()
    iex> changeset.errors
    [allow_list: {"Invalid CIDR range: 0.0.0.0", []}]

    iex> changeset =
    iex> Ecto.Changeset.change(%Ultravisor.Tenants.Tenant{}, %{allow_list: ["0.0.0.0/0", "::/0"]})
    iex> |> Ultravisor.Tenants.Tenant.validate_allow_list()
    iex> changeset.errors
    []

    iex> changeset =
    iex> Ecto.Changeset.change(%Ultravisor.Tenants.Tenant{}, %{allow_list: ["0.0.0.0/0", "foo", "bar"]})
    iex> |> Ultravisor.Tenants.Tenant.validate_allow_list()
    iex> changeset.errors
    [{:allow_list, {"Invalid CIDR range: foo", []}}, {:allow_list, {"Invalid CIDR range: bar", []}}]

    iex> changeset =
    iex> Ecto.Changeset.change(%Ultravisor.Tenants.Tenant{}, %{allow_list: ["0.0.0.0/0   "]})
    iex> |> Ultravisor.Tenants.Tenant.validate_allow_list()
    iex> changeset.errors
    []
  """

  @spec validate_allow_list(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_allow_list(changeset) do
    validate_change(changeset, :allow_list, fn :allow_list, value when is_list(value) ->
      for range <- value, !valid_range?(range) do
        {:allow_list, "Invalid CIDR range: #{range}"}
      end
    end)
  end

  defp valid_range?(range) do
    match?({:ok, _}, InetCidr.parse_cidr(range))
  end
end
