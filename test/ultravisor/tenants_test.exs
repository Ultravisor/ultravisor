# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.TenantsTest do
  use Ultravisor.DataCase

  @subject Ultravisor.Tenants

  describe "tenants" do
    alias Ultravisor.Tenants.Tenant
    alias Ultravisor.Tenants.User

    import Ultravisor.TenantsFixtures

    @invalid_attrs %{
      db_database: nil,
      db_host: nil,
      external_id: nil,
      default_parameter_status: nil,
      allow_list: ["foo", "bar"]
    }

    test "get_tenant!/1 returns the tenant with given id" do
      tenant = tenant_fixture()
      assert @subject.get_tenant!(tenant.id) |> Repo.preload(:users) == tenant
    end

    test "create_tenant/1 with valid data creates a tenant" do
      user_valid_attrs = %{
        "db_user" => "some db_user",
        "db_password" => "some db_password",
        "pool_size" => 3,
        "require_user" => true,
        "mode_type" => "transaction"
      }

      valid_attrs = %{
        db_host: "some db_host",
        db_port: 42,
        db_database: "some db_database",
        external_id: "dev_tenant",
        default_parameter_status: %{"server_version" => "15.0"},
        require_user: true,
        users: [user_valid_attrs],
        allow_list: ["71.209.249.38/32"]
      }

      assert {:ok, %Tenant{users: [%User{} = user]} = tenant} =
               @subject.create_tenant(valid_attrs)

      assert tenant.db_database == "some db_database"
      assert tenant.db_host == "some db_host"
      assert tenant.db_port == 42
      assert tenant.external_id == "dev_tenant"
      assert tenant.allow_list == ["71.209.249.38/32"]
      assert user.db_password == "some db_password"
      assert user.db_user == "some db_user"
      assert user.pool_size == 3
    end

    test "create_tenant/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = @subject.create_tenant(@invalid_attrs)
    end

    test "update_tenant/2 with invalid data returns error changeset" do
      tenant = tenant_fixture()
      assert {:error, %Ecto.Changeset{}} = @subject.update_tenant(tenant, @invalid_attrs)
      assert tenant == @subject.get_tenant!(tenant.id) |> Repo.preload(:users)
    end

    test "delete_tenant_by_external_id/1 deletes the tenant" do
      tenant = tenant_fixture()
      assert @subject.delete_tenant_by_external_id(tenant.external_id)
      assert_raise Ecto.NoResultsError, fn -> @subject.get_tenant!(tenant.id) end
    end

    test "change_tenant/1 returns a tenant changeset" do
      tenant = tenant_fixture()
      assert %Ecto.Changeset{} = @subject.change_tenant(tenant)
    end

    test "get_user/4" do
      _tenant = tenant_fixture()
      assert {:error, :not_found} = @subject.get_user(:single, "no_user", "no_tenant", "")

      assert {:ok, %{tenant: _, user: _}} =
               @subject.get_user(:single, "postgres", "dev_tenant", "")
    end
  end
end
