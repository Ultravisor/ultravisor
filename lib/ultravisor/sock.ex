# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Sock do
  @moduledoc """
  Provides common operations for TCP and SSL sockets.

  Socket values use a tagged tuple: `{:gen_tcp, socket}` for TCP sockets and
  `{:ssl, socket}` for SSL sockets. The tag selects the Erlang socket module
  used by each operation.

  `send/2`, `setopts/2`, and `close/1` delegate to the matching socket module.
  `send_error/3` sends a PostgreSQL error message. `try_get_sni/1` returns the
  TLS server name when available, or `nil`. `addr/1` returns the peer IP
  address, or `:error` when the peer address is unavailable or is not an IP
  address.
  """

  import Kernel, except: [send: 2]

  alias Ultravisor.Protocol.Server

  @type t() :: tcp() | ssl()

  @type ssl() :: {:ssl, :ssl.sslsocket()}
  @type tcp() :: {:gen_tcp, :gen_tcp.socket()}

  @spec send(t(), iodata()) :: :ok | {:error, term()}
  def send({:gen_tcp, sock}, data), do: :gen_tcp.send(sock, data)
  def send({:ssl, sock}, data), do: :ssl.send(sock, data)

  @spec close(t() | nil | {any(), nil}) :: :ok | {:error, term()}
  def close(nil), do: :ok
  def close({_, nil}), do: :ok

  def close({mod, sock}), do: mod.close(sock)

  @spec setopts(t(), term()) :: :ok | {:error, term()}
  def setopts({:gen_tcp, sock}, opts), do: :inet.setopts(sock, opts)
  def setopts({:ssl, sock}, opts), do: :ssl.setopts(sock, opts)

  @spec send_error(Ultravisor.sock(), String.t(), String.t()) :: :ok | {:error, term()}
  def send_error(sock, code, message) do
    data = Server.error_message(code, message)
    send(sock, data)
  end

  @spec try_get_sni(Ultravisor.sock()) :: String.t() | nil
  def try_get_sni({:ssl, sock}) do
    case :ssl.connection_information(sock, [:sni_hostname]) do
      {:ok, [sni_hostname: sni]} -> List.to_string(sni)
      _ -> nil
    end
  end

  def try_get_sni(_), do: nil

  @spec addr(t()) :: {:ok, :inet.ip_address()} | :error
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
