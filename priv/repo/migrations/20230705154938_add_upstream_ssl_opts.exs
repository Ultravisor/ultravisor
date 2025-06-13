# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.AddUpstreamSslOpts do
  use Ecto.Migration

  def up do
    alter table("tenants", prefix: "_ultravisor") do
      add(:upstream_ssl, :boolean, null: false, default: false)
      add(:upstream_verify, :string, null: true)
      add(:upstream_tls_ca, :binary, null: true)
    end

    create(
      constraint(
        "tenants",
        :upstream_verify_values,
        check: "upstream_verify IN ('none', 'peer')",
        prefix: "_ultravisor"
      )
    )

    upstream_constraints = """
    (upstream_ssl = false AND upstream_verify IS NULL) OR (upstream_ssl = true AND upstream_verify IS NOT NULL)
    """

    create(
      constraint("tenants", :upstream_constraints,
        check: upstream_constraints,
        prefix: "_ultravisor"
      )
    )
  end

  def down do
    alter table("tenants", prefix: "_ultravisor") do
      remove(:upstream_ssl)
      remove(:upstream_verify)
      remove(:upstream_tls_ca_encrypted)
    end

    drop(constraint("tenants", "upstream_verify_values", prefix: "_ultravisor"))
    drop(constraint("tenants", "upstream_constraints", prefix: "_ultravisor"))
  end
end
