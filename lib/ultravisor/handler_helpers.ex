# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.HandlerHelpers do
  @moduledoc false

  alias Phoenix.PubSub

  require Ultravisor.Protocol.Server, as: Server

  @spec parse_user_info(map) ::
          {String.t() | nil, String.t(), String.t() | nil}
  def parse_user_info(%{"user" => user, "options" => %{"reference" => ref}} = payload) do
    # TODO: parse ref for cluster
    {user, ref, payload["database"]}
  end

  def parse_user_info(%{"user" => user} = payload) do
    db_name = payload["database"]

    case :binary.matches(user, ".") do
      [] ->
        {user, nil, db_name}

      matches ->
        {pos, 1} = List.last(matches)
        <<name::size(^pos)-binary, ?., external_id::binary>> = user
        {name, external_id, db_name}
    end
  end

  @spec send_cancel_query(non_neg_integer(), non_neg_integer()) :: :ok | {:errr, term}
  def send_cancel_query(pid, key) do
    PubSub.broadcast(
      Ultravisor.PubSub,
      "cancel_req:#{pid}_#{key}",
      :cancel_query
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
    :ok = Ultravisor.Sock.send(sock, msg)
    :ok = Ultravisor.Sock.close(sock)
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
end
