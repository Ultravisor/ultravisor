# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Config do
  @moduledoc """
  Helper functions for fetching configuration options from system environment
  """

  @doc """
  Read environment variable and try to cast it to boolean.

  Values treated as `false` are `0` and `false`. Any other value (including
  empty variable) is treated as `true`.
  """
  @spec get_bool(String.t()) :: boolean()
  @spec get_bool(String.t(), boolean()) :: boolean()
  def get_bool(env_name, default \\ true) do
    case System.fetch_env(env_name) do
      {:ok, falsey} when falsey in ~w[0 false] -> false
      {:ok, _} -> true
      :error -> default
    end
  end

  @doc """
  Read environment variable and try to cast it to integer
  """
  @spec get_integer(String.t()) :: integer() | nil
  @spec get_integer(String.t(), integer() | nil) :: integer() | nil
  def get_integer(env_name, default \\ nil) do
    case System.fetch_env(env_name) do
      {:ok, env} -> String.to_integer(env)
      :error -> default
    end
  end

  @doc """
  Read environment variable and try to cast it to one of the predefined atoms
  """
  @spec get_enum(String.t(), [atom()]) :: atom() | nil
  @spec get_enum(String.t(), [atom()], atom() | nil) :: atom() | nil
  def get_enum(env_name, allowed_values, default \\ nil) do
    case System.fetch_env(env_name) do
      {:ok, env} ->
        mapping = Map.new(allowed_values, &{Atom.to_string(&1), &1})

        mapping[env] ||
          raise "#{env_name} value is invalid, got: #{inspect(env)}, expected one of: #{inspect(Map.keys(mapping))}"

      :error ->
        default
    end
  end

  @doc """
  Read environment variable and split comma separated values from it

  Omits empty values.
  """
  @spec get_list(String.t()) :: [String.t()]
  @spec get_list(String.t(), [String.t()]) :: [String.t()]
  def get_list(env_name, default \\ []) do
    case System.fetch_env(env_name) do
      {:ok, env} -> String.split(env, ",", trim: true)
      :error -> default
    end
  end

  @doc """
  Read environment variable and try to extract JSON data stored in it
  """
  @spec get_json(String.t()) :: map()
  @spec get_json(String.t(), map()) :: map()
  def get_json(env_name, default \\ %{}) do
    case System.fetch_env(env_name) do
      {:ok, env} -> JSON.decode!(env)
      :error -> default
    end
  end
end
