# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Sock.Default do
  @moduledoc false

  import Kernel, except: [send: 2]

  alias Ultravisor.Protocol.Server

  @behaviour Ultravisor.Sock

  @impl true
  @spec send(Ultravisor.Sock.t(), iodata()) :: :ok | {:error, term()}
  def send({:gen_tcp, sock}, data), do: :gen_tcp.send(sock, data)
  def send({:ssl, sock}, data), do: :ssl.send(sock, data)

  @impl true
  @spec close(Ultravisor.Sock.t() | nil | {any(), nil}) :: :ok | {:error, term()}
  def close(nil), do: :ok
  def close({_, nil}), do: :ok

  def close({mod, sock}), do: mod.close(sock)

  @impl true
  @spec setopts(Ultravisor.Sock.t(), term()) :: :ok | {:error, term()}
  def setopts({:gen_tcp, sock}, opts), do: :inet.setopts(sock, opts)
  def setopts({:ssl, sock}, opts), do: :ssl.setopts(sock, opts)

  @impl true
  @spec send_error(Ultravisor.sock(), String.t(), String.t()) :: :ok | {:error, term()}
  def send_error(sock, code, message) do
    data = Server.error_message(code, message)
    send(sock, data)
  end

  @impl true
  @spec try_get_sni(Ultravisor.sock()) :: String.t() | nil
  def try_get_sni({:ssl, sock}) do
    case :ssl.connection_information(sock, [:sni_hostname]) do
      {:ok, [sni_hostname: sni]} -> List.to_string(sni)
      _ -> nil
    end
  end

  def try_get_sni(_), do: nil

  @impl true
  @spec addr(Ultravisor.Sock.t()) :: {:ok, :inet.ip_address()} | :error
  def addr({:gen_tcp, port}) do
    case :inet.peername(port) do
      {:ok, {:local, _}} ->
        :error

      {:ok, {:undefined, _}} ->
        :error

      {:ok, {:unspec, _}} ->
        :error

      {:ok, {addr, _port}} ->
        {:ok, addr}

      {:error, _} ->
        :error
    end
  end

  def addr({:ssl, port}) do
    case :ssl.peername(port) do
      {:ok, {addr, _port}} ->
        {:ok, addr}

      {:error, _} ->
        :error
    end
  end
end
