# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Ecto.Cert do
  @moduledoc """
  Ecto type for storing SSL/TLS certificate.

  It accepts PEM encoded certificate (must be unencrypted) or direct binary
  certificate data.
  """

  use Ecto.Type

  @guard "-----BEGIN CERTIFICATE-----"

  @impl true
  def type, do: :binary

  @impl true
  def cast(@guard <> _ = cert) do
    case :public_key.pem_decode(cert) do
      [] ->
        :error

      entries ->
        cert = for {:Certificate, cert, :not_encrypted} <- entries, do: cert

        case cert do
          [cert] -> {:ok, cert}
          _ -> :error
        end
    end
  end

  def cast(cert) when is_binary(cert), do: {:ok, cert}
  def cast(_), do: :error

  @impl true
  def load(data) when is_binary(data), do: {:ok, data}
  def load(_), do: :error

  @impl true
  def dump(data) when is_binary(data), do: {:ok, data}
  def dump(_), do: :error
end
