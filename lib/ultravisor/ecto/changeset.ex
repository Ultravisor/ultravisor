# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Ecto.Changeset do
  @moduledoc """
  `Ecto.Changeset` helper functions
  """

  @doc """
  Insert default values into changeset if the fields are unset.

  See `add_default/3`.
  """
  def with_defaults(changeset, defaults) do
    Enum.reduce(defaults, changeset, fn {key, value}, changeset ->
      add_default(changeset, key, value)
    end)
  end

  @doc """
  Add `value` under `key` to `changeset` if the key is unset
  """
  def add_default(changeset, key, value) do
    if Ecto.Changeset.get_field(changeset, key) do
      changeset
    else
      Ecto.Changeset.put_change(changeset, key, value)
    end
  end
end
