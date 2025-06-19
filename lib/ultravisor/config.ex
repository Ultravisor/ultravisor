defmodule Ultravisor.Config do
  def get_bool(env_name, default \\ true) do
    case System.fetch_env(env_name) do
      {:ok, falsey} when falsey in ~w[0 false] -> false
      {:ok, _} -> true
      :error -> default
    end
  end

  def get_json_map(env_name, default \\ %{}) do
    with {:ok, env} <- System.fetch_env(env_name),
         {:ok, decoded} <- JSON.decode(env),
         true <- is_map(decoded) do
      decoded
    else
      _ -> default
    end
  end
end
