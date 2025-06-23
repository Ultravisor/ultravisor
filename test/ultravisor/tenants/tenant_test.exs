# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Tenants.TenantTest do
  use ExUnit.Case, async: true

  @subject Ultravisor.Tenants.Tenant

  doctest @subject

  describe "changeset/2" do
    test "required fields" do
      attrs = %{
        default_parameter_status: %{},
        external_id: "some_id",
        db_host: "localhost",
        db_port: 2137,
        db_database: "example"
      }

      changeset = @subject.changeset(%@subject{}, attrs)

      assert changeset.valid?
    end

    test "certificate is properly decoded" do
      pem = File.read!("test/fixtures/example.cert.pem")
      [{:Certificate, cert, _}] = :public_key.pem_decode(pem)

      attrs = %{
        default_parameter_status: %{},
        external_id: "some_id",
        db_host: "localhost",
        db_port: 2137,
        db_database: "example",
        upstream_tls_ca: pem
      }

      changeset = @subject.changeset(%@subject{}, attrs)

      assert changeset.valid?
      assert cert == Ecto.Changeset.get_change(changeset, :upstream_tls_ca)
    end
  end
end
