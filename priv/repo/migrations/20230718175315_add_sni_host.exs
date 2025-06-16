# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.AddSniHost do
  use Ecto.Migration

  def change do
    alter table("tenants", prefix: "_ultravisor") do
      add(:sni_hostname, :string, null: true)
    end
  end
end
