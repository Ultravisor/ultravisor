# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Tenants do
  @moduledoc """
  The Tenants context.
  """

  import Ecto.Query, warn: false
  alias Ultravisor.Repo

  alias Ultravisor.Tenants.Tenant
  alias Ultravisor.Tenants.User

  @doc """
  Returns the list of tenants.

  ## Examples

      iex> list_tenants()
      [%Tenant{}, ...]

  """
  def list_tenants do
    Repo.all(Tenant) |> Repo.preload([:users])
  end

  @doc """
  Gets a single tenant.

  Raises `Ecto.NoResultsError` if the Tenant does not exist.

  ## Examples

      iex> get_tenant!(123)
      %Tenant{}

      iex> get_tenant!(456)
      ** (Ecto.NoResultsError)

  """
  def get_tenant!(id), do: Repo.get!(Tenant, id)

  @spec get_tenant_by_external_id(String.t()) :: Tenant.t() | nil
  def get_tenant_by_external_id(external_id) do
    Tenant |> Repo.get_by(external_id: external_id) |> Repo.preload(:users)
  end

  @spec get_tenant_cache(String.t() | nil, String.t() | nil) :: Tenant.t() | nil
  def get_tenant_cache(external_id, sni_hostname) do
    cache_key = {:tenant_cache, external_id, sni_hostname}

    {_, {:cached, value}} =
      Cachex.fetch(Ultravisor.Cache, cache_key, fn _key ->
        {:commit, {:cached, get_tenant(external_id, sni_hostname)}, expire: :timer.hours(24)}
      end)

    value
  end

  @spec get_tenant(String.t() | nil, String.t() | nil) :: Tenant.t() | nil
  def get_tenant(nil, sni) when sni != nil do
    Tenant |> Repo.get_by(sni: sni)
  end

  def get_tenant(external_id, _) when external_id != nil do
    Tenant |> Repo.get_by(external_id: external_id)
  end

  def get_tenant(_, _), do: nil

  @spec get_user_cache(:single | :cluster, String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, map()} | {:error, any()}
  def get_user_cache(type, user, external_id, sni_hostname) do
    cache_key = {:user_cache, type, user, external_id, sni_hostname}

    {_, {:cached, value}} =
      Cachex.fetch(Ultravisor.Cache, cache_key, fn _key ->
        {:commit, {:cached, get_user(type, user, external_id, sni_hostname)},
         expire: :timer.hours(24)}
      end)

    value
  end

  @spec get_user(atom(), String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, map()} | {:error, any()}
  def get_user(_, _, nil, nil) do
    {:error, "Either external_id or sni_hostname must be provided"}
  end

  def get_user(:single, user, external_id, sni_hostname) do
    query = build_user_query(user, external_id, sni_hostname)

    case Repo.all(query) do
      [{%User{}, %Tenant{}} = {user, tenant}] ->
        {:ok, %{user: user, tenant: tenant}}

      [_ | _] ->
        {:error, :multiple_results}

      _ ->
        {:error, :not_found}
    end
  end

  def get_pool_config(external_id, user) do
    query =
      from(a in User,
        where: a.db_user_alias == ^user
      )

    Repo.all(
      from(p in Tenant,
        where: p.external_id == ^external_id,
        preload: [users: ^query]
      )
    )
  end

  def get_pool_config_cache(external_id, user, ttl \\ :timer.hours(24)) do
    ttl = if is_nil(ttl), do: :timer.hours(24), else: ttl
    cache_key = {:pool_config_cache, external_id, user}

    {_, {:cached, value}} =
      Cachex.fetch(Ultravisor.Cache, cache_key, fn _key ->
        {:commit, {:cached, get_pool_config(external_id, user)}, expire: ttl}
      end)

    value
  end

  @doc """
  Creates a tenant.

  ## Examples

      iex> create_tenant(%{field: value})
      {:ok, %Tenant{}}

      iex> create_tenant(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_tenant(attrs \\ %{}) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a tenant.

  ## Examples

      iex> update_tenant(tenant, %{field: new_value})
      {:ok, %Tenant{}}

      iex> update_tenant(tenant, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_tenant(%Tenant{} = tenant, attrs) do
    tenant
    |> Tenant.changeset(attrs)
    |> Repo.update()
  end

  def update_tenant_ps(external_id, new_ps) do
    from(t in Tenant, where: t.external_id == ^external_id)
    |> Repo.one()
    |> Tenant.changeset(%{default_parameter_status: new_ps})
    |> Repo.update()
  end

  @spec delete_tenant_by_external_id(String.t()) :: boolean()
  def delete_tenant_by_external_id(id) do
    from(t in Tenant, where: t.external_id == ^id)
    |> Repo.delete_all()
    |> case do
      {num, _} when num > 0 ->
        true

      _ ->
        false
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking tenant changes.

  ## Examples

      iex> change_tenant(tenant)
      %Ecto.Changeset{data: %Tenant{}}

  """
  def change_tenant(%Tenant{} = tenant, attrs \\ %{}) do
    Tenant.changeset(tenant, attrs)
  end

  @spec build_user_query(String.t(), String.t() | nil, String.t() | nil) ::
          Ecto.Queryable.t()
  defp build_user_query(user, external_id, sni_hostname) do
    from(u in User,
      join: t in Tenant,
      on: u.tenant_external_id == t.external_id,
      where:
        (u.db_user_alias == ^user and t.require_user == true) or
          (t.require_user == false and u.is_manager == true),
      select: {u, t}
    )
    |> where(^with_tenant(external_id, sni_hostname))
  end

  defp with_tenant(nil, sni_hostname) do
    dynamic([_, t], t.sni_hostname == ^sni_hostname)
  end

  defp with_tenant(external_id, _) do
    dynamic([_, t], t.external_id == ^external_id)
  end
end
