# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Repo.Migrations.CreatePostgresSchema do
  use Ecto.Migration

  def up do
    execute ~S[CREATE SCHEMA IF NOT EXISTS "_ultravisor"]
  end

  def down do
    execute ~S[DROP SCHEMA "_ultravisor"]
  end
end
