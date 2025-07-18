# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.HandlerHelpers do
  @moduledoc false

  alias Phoenix.PubSub

  require Ultravisor.Protocol.Server, as: Server

  @spec sock_send(Ultravisor.sock(), iodata()) :: :ok | {:error, term()}
  def sock_send({mod, sock}, data) do
    mod.send(sock, data)
  end

  @spec sock_close(Ultravisor.sock() | nil | {any(), nil}) :: :ok | {:error, term()}
  def sock_close(nil), do: :ok
  def sock_close({_, nil}), do: :ok

  def sock_close({mod, sock}), do: mod.close(sock)

  @spec setopts(Ultravisor.sock(), term()) :: :ok | {:error, term()}
  def setopts({mod, sock}, opts) do
    mod = if mod == :gen_tcp, do: :inet, else: mod
    mod.setopts(sock, opts)
  end

  @spec active_once(Ultravisor.sock()) :: :ok | {:error, term}
  def active_once(sock), do: setopts(sock, active: :once)

  @spec activate(Ultravisor.sock()) :: :ok | {:error, term}
  def activate(sock), do: setopts(sock, active: true)

  @spec try_ssl_handshake(Ultravisor.tcp_sock(), boolean) ::
          {:ok, Ultravisor.sock()} | {:error, term()}
  def try_ssl_handshake(sock, true) do
    case sock_send(sock, Server.ssl_request()) do
      :ok -> ssl_recv(sock)
      error -> error
    end
  end

  def try_ssl_handshake(sock, false), do: {:ok, sock}

  @spec ssl_recv(Ultravisor.tcp_sock()) :: {:ok, Ultravisor.ssl_sock()} | {:error, term}
  def ssl_recv({:gen_tcp, sock} = s) do
    case :gen_tcp.recv(sock, 1, 15_000) do
      {:ok, <<?S>>} -> ssl_connect(s)
      {:ok, <<?N>>} -> {:ok, s}
      {:error, _} = error -> error
    end
  end

  @spec ssl_connect(Ultravisor.tcp_sock(), pos_integer) ::
          {:ok, Ultravisor.ssl_sock()} | {:error, term}
  def ssl_connect({:gen_tcp, sock}, timeout \\ 5000) do
    opts = [verify: :verify_none]

    case :ssl.connect(sock, opts, timeout) do
      {:ok, ssl_sock} -> {:ok, {:ssl, ssl_sock}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec send_error(Ultravisor.sock(), String.t(), String.t()) :: :ok | {:error, term()}
  def send_error(sock, code, message) do
    data = Server.error_message(code, message)
    sock_send(sock, data)
  end

  @spec try_get_sni(Ultravisor.sock()) :: String.t() | nil
  def try_get_sni({:ssl, sock}) do
    case :ssl.connection_information(sock, [:sni_hostname]) do
      {:ok, [sni_hostname: sni]} -> List.to_string(sni)
      _ -> nil
    end
  end

  def try_get_sni(_), do: nil

  @spec parse_user_info(map) ::
          {:cluster | :single, {String.t() | nil, String.t(), String.t() | nil}}
  def parse_user_info(%{"user" => user, "options" => %{"reference" => ref}} = payload) do
    # TODO: parse ref for cluster
    {:single, {user, ref, payload["database"]}}
  end

  def parse_user_info(%{"user" => user} = payload) do
    db_name = payload["database"]

    case :binary.split(user, ".cluster.") do
      [user] ->
        case :binary.matches(user, ".") do
          [] ->
            {:single, {user, nil, db_name}}

          matches ->
            {pos, 1} = List.last(matches)
            <<name::size(pos)-binary, ?., external_id::binary>> = user
            {:single, {name, external_id, db_name}}
        end

      [user, tenant] ->
        {:cluster, {user, tenant, db_name}}
    end
  end

  @spec send_cancel_query(non_neg_integer, non_neg_integer, term) :: :ok | {:errr, term}
  def send_cancel_query(pid, key, msg \\ :cancel_query) do
    PubSub.broadcast(
      Ultravisor.PubSub,
      "cancel_req:#{pid}_#{key}",
      msg
    )
  end

  @spec listen_cancel_query(non_neg_integer, non_neg_integer) :: :ok | {:errr, term}
  def listen_cancel_query(pid, key) do
    PubSub.subscribe(Ultravisor.PubSub, "cancel_req:#{pid}_#{key}")
  end

  @spec cancel_query(keyword, non_neg_integer, atom, non_neg_integer, non_neg_integer) :: :ok
  def cancel_query(host, port, ip_version, pid, key) do
    msg = Server.cancel_message(pid, key)
    opts = [:binary, {:packet, :raw}, {:active, true}, ip_version]
    {:ok, sock} = :gen_tcp.connect(host, port, opts)
    sock = {:gen_tcp, sock}
    :ok = sock_send(sock, msg)
    :ok = sock_close(sock)
  end

  @doc """
  Takes an allow list of CIDR ranges and filtres them for ranges which contain the address
  to test.

  If the IP address of the socket is not found an empty list is returned.

  ## Examples

    iex> Ultravisor.HandlerHelpers.filter_cidrs(["0.0.0.0/0", "::/0"], {127, 0, 0, 1})
    ["0.0.0.0/0"]

    iex> Ultravisor.HandlerHelpers.filter_cidrs(["71.209.249.38/32"], {71, 209, 249, 39})
    []

    iex> Ultravisor.HandlerHelpers.filter_cidrs(["0.0.0.0/0", "::/0"], {8193, 3512, 34211, 0, 0, 35374, 880, 29492})
    ["::/0"]

    iex> Ultravisor.HandlerHelpers.filter_cidrs(["0.0.0.0/0", "::/0"], :error)
    []

  """

  @spec filter_cidrs(list(), :inet.ip_address() | any()) :: list()
  def filter_cidrs(allow_list, addr) when is_list(allow_list) and is_tuple(addr) do
    for range <- allow_list,
        range |> InetCidr.parse_cidr!() |> InetCidr.contains?(addr) do
      range
    end
  end

  def filter_cidrs(allow_list, _addr) when is_list(allow_list) do
    []
  end

  @spec addr_from_sock(Ultravisor.sock()) :: {:ok, :inet.ip_address()} | :error
  def addr_from_sock({:gen_tcp, port}) do
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

  def addr_from_sock({:ssl, port}) do
    case :ssl.peername(port) do
      {:ok, {addr, _port}} ->
        {:ok, addr}

      {:error, _} ->
        :error
    end
  end
end
