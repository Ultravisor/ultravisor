# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.PgParser do
  @moduledoc false

  use Rustler, otp_app: :ultravisor, crate: "pgparser"

  # When your NIF is loaded, it will override this function.
  @doc """
  Returns a list of all statements in the given sql string.

  ## Examples

      iex> Ultravisor.PgParser.statement_types("select 1; insert into table1 values ('a', 'b')")
      {:ok, ["SelectStmt", "InsertStmt"]}

      iex> Ultravisor.PgParser.statement_types("not a valid sql")
      {:error, "Error parsing query"}
  """
  @spec statement_types(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def statement_types(_query), do: :erlang.nif_error(:nif_not_loaded)

  @spec statements(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def statements(query) when is_binary(query), do: statement_types(query)
  def statements(_), do: {:error, "Query must be a string"}
end
