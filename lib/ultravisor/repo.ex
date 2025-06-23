# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo do
  use Ecto.Repo,
    otp_app: :ultravisor,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query

  def fetch_by(queryable, selectors) do
    query =
      from queryable, where: ^selectors, limit: 1

    case all(query) do
      [] -> {:error, :not_found}
      [row] -> {:ok, row}
    end
  end
end
