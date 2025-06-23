# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Config do
  def get_bool(env_name, default \\ true) do
    case System.fetch_env(env_name) do
      {:ok, falsey} when falsey in ~w[0 false] -> false
      {:ok, _} -> true
      :error -> default
    end
  end

  def get_integer(env_name, default \\ nil) do
    case System.fetch_env(env_name) do
      {:ok, env} -> String.to_integer(env)
      :error -> default
    end
  end

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

  def get_list(env_name, default \\ []) do
    case System.fetch_env(env_name) do
      {:ok, env} -> String.split(env, ",", trim: true)
      :error -> default
    end
  end

  def get_json(env_name, default \\ %{}) do
    case System.fetch_env(env_name) do
      {:ok, env} -> JSON.decode!(env)
      :error -> default
    end
  end
end
