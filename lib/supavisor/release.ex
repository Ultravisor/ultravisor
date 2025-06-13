# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :ultravisor

  def migrate do
    ensure_ssl_started()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          &Ecto.Migrator.run(&1, :up, all: true, prefix: "_ultravisor")
        )
    end
  end

  def rollback(repo, version) do
    ensure_ssl_started()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(
        repo,
        &Ecto.Migrator.run(&1, :down, to: version, prefix: "_ultravisor")
      )
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp ensure_ssl_started do
    Application.ensure_all_started(:ssl)
  end
end
