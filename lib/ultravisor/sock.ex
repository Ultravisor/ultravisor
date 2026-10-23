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

  This module declares the socket contract and forwards each call to the
  implementation module that `impl/0` returns. `Ultravisor.Sock.Default` is the
  default implementation. The value of `:ultravisor_sock_impl` in the process
  dictionary selects the implementation module for the current process. A test
  sets that key to use a mock in place of the real socket operations.
  """

  @type t() :: tcp() | ssl()

  @type ssl() :: {:ssl, :ssl.sslsocket()}
  @type tcp() :: {:gen_tcp, :gen_tcp.socket()}

  @callback send(t(), iodata()) :: :ok | {:error, term()}
  @callback close(t() | nil | {any(), nil}) :: :ok | {:error, term()}
  @callback setopts(t(), term()) :: :ok | {:error, term()}
  @callback send_error(Ultravisor.sock(), String.t(), String.t()) :: :ok | {:error, term()}
  @callback try_get_sni(Ultravisor.sock()) :: String.t() | nil
  @callback addr(t()) :: {:ok, :inet.ip_address()} | :error

  @spec send(t(), iodata()) :: :ok | {:error, term()}
  def send(sock, data), do: impl().send(sock, data)

  @spec close(t() | nil | {any(), nil}) :: :ok | {:error, term()}
  def close(sock), do: impl().close(sock)

  @spec setopts(t(), term()) :: :ok | {:error, term()}
  def setopts(sock, opts), do: impl().setopts(sock, opts)

  @spec send_error(Ultravisor.sock(), String.t(), String.t()) :: :ok | {:error, term()}
  def send_error(sock, code, message), do: impl().send_error(sock, code, message)

  @spec try_get_sni(Ultravisor.sock()) :: String.t() | nil
  def try_get_sni(sock), do: impl().try_get_sni(sock)

  @spec addr(t()) :: {:ok, :inet.ip_address()} | :error
  def addr(sock), do: impl().addr(sock)

  @spec impl() :: module()
  defp impl, do: Process.get(:ultravisor_sock_impl, Ultravisor.Sock.Default)
end
