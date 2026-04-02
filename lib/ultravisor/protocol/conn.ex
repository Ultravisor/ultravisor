# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.Conn do
  alias Ultravisor.Protocol.Server

  defstruct socket: nil,
            owner: nil,
            parameters: %{}

  def connect(host, port, opts) do
    sock_opts =
      Access.get(opts, :sock_opts, []) ++
        [
          mode: :binary,
          packet: :raw,
          active: false
        ]

    with {:ok, sock} <- :gen_tcp.connect(to_charlist(host), port, sock_opts) do
      conn = %__MODULE__{
        socket: {:gen_tcp, sock},
        owner: self()
      }

      setup(conn, opts)
    end
  end

  defp setup(%__MODULE__{} = conn, opts) do
    case Access.get(opts, :ssl, false) do
      false -> setup_startup(conn, opts)
      true -> setup_ssl(conn, opts, [])
      ssl_opts -> setup_ssl(conn, opts, ssl_opts)
    end
  end

  defp setup_ssl(%__MODULE__{} = _conn, _opts, _ssl_opts) do
    raise "Unimplemented"
  end

  defp setup_startup(%__MODULE__{} = conn, opts) do
    user = Access.fetch!(opts, :user)
    database = Access.fetch!(opts, :database)

    search_path = Access.get(opts, :search_path)

    connection_params =
      Access.get(opts, :connection_params, []) ++
        if(search_path, do: [{"options", "--search_path=#{search_path}"}], else: [])

    msg =
      :pgo_protocol.encode_startup_message([
        {"user", user},
        {"database", database}
        | connection_params
      ])

    with :ok <- send_msg(conn.socket, msg),
         {:ok, msg} <- recv_msg(conn.socket) do
      case msg do
        %Server.Pkt{tag: :error_response, payload: error_fields} ->
          {:error, {:postgres_error, error_fields}}

        %Server.Pkt{tag: :authentication, payload: :authentication_ok} ->
          setup_finish(conn)

        %Server.Pkt{tag: :authentication, payload: :authentication_cleartext_password} ->
          # setup_authentication_cleartext_password(conn, opts)
          {:error, {:unsupported, :authentication_cleartext_password}}

        %Server.Pkt{tag: :authentication, payload: {:authentication_md5_password, salt}} ->
          setup_authentication_md5_password(conn, opts, salt)

        %Server.Pkt{
          tag: :authentication,
          payload: {:authentication_sasl_password, methods_binary}
        } ->
          setup_authentication_sasl_password(conn, methods_binary, opts)

        %Server.Pkt{tag: :authentication, payload: payload} ->
          {:error, {:unimplemented, payload}}

        %Server.Pkt{} = packet ->
          {:error, {:unexpected_msg, packet}}
      end
    end
  end

  defp setup_finish(%__MODULE__{} = conn) do
    case recv_msg(conn.socket) do
      {:ok, %Server.Pkt{tag: :error_response, payload: error_fields}} ->
        {:error, {:postgres_error, error_fields}}

      {:ok, %Server.Pkt{tag: :parameter_status, payload: {k, v}}} ->
        # Kernel.send(conn.owner, {:parameter_status, k, v})
        setup_finish(%{conn | parameters: Map.put(conn.parameters, k, v)})

      {:ok, %Server.Pkt{tag: :backend_key_data}} ->
        setup_finish(conn)

      {:ok, %Server.Pkt{tag: :ready_for_query}} ->
        {:ok, conn}

      {:ok, %Server.Pkt{tag: :authentication, payload: :authentication_ok}} ->
        setup_finish(conn)

      {:ok, packet} ->
        {:error, {:unexpected_msg, packet}}

      {:error, _} = error ->
        error
    end
  end

  defp setup_authentication_sasl_password(%__MODULE__{} = conn, methods_bin, opts) do
    methods = :pgo_protocol.decode_strings(methods_bin)

    if "SCRAM-SHA-256" in methods do
      auth_scram(conn, opts)
    else
      {:error, {:unimplemented, {:sasl, methods}}}
    end
  end

  defp auth_scram(conn, opts) do
    nonce = :pgo_scram.get_nonce(16)

    with {:ok, %Server.Pkt{payload: {:authentication_server_first_message, fst}}} <-
           scram_client_first(nonce, conn, opts),
         {{:ok, %Server.Pkt{payload: {:authentication_server_final_message, fin}}}, proof} <-
           scram_client_final(nonce, fst, conn, opts) do
      case :pgo_scram.parse_server_final(fin) do
        {:ok, ^proof} ->
          setup_finish(conn)

        other ->
          {:error, {:sasl_server_final, other}}
      end
    else
      {:ok, msg} ->
        {:error, {:unexpected_msg, msg}}

      {:error, _} = error ->
        error
    end
  end

  defp scram_client_first(nonce, %__MODULE__{} = conn, opts) do
    user = opts[:user]
    client_first = :pgo_scram.get_client_first(user, nonce)
    client_first_size = IO.iodata_length(client_first)
    response = ["SCRAM-SHA-256", 0, <<client_first_size::32>>, client_first]

    with :ok <- send_msg(conn.socket, :pgo_protocol.encode_scram_response_message(response)),
         do: recv_msg(conn.socket)
  end

  defp scram_client_final(nonce, first, conn, opts) do
    user = opts[:user]
    parts = :pgo_scram.parse_server_first(first, nonce)
    password = opts[:password]
    {final_msg, proof} = :pgo_scram.get_client_final(parts, nonce, user, password)

    with :ok <- send_msg(conn.socket, :pgo_protocol.encode_scram_response_message(final_msg)) do
      {recv_msg(conn.socket), proof}
    end
  end

  defp setup_authentication_md5_password(%__MODULE__{} = conn, salt, opts) do
    secret =
      case Access.get(opts, :secret) do
        nil ->
          user = opts[:user]
          password = opts[:password] || ""

          :crypto.hash(:md5, [password, user])
          |> Base.encode16(case: :lower)

        secret ->
          secret
      end

    challenge =
      :crypto.hash(:md5, [secret, salt])
      |> Base.encode16(case: :lower)

    setup_authenticate_password(conn, ["md5", challenge])
  end

  defp setup_authenticate_password(%__MODULE__{} = conn, password) do
    message = :pgo_protocol.encode_password_message(password)

    with :ok <- send_msg(conn.socket, message),
         {:ok, packet} <- recv_msg(conn.socket) do
      case packet do
        %Server.Pkt{tag: :error_response, payload: error_fields} ->
          {:error, {:postgres_error, error_fields}}

        %Server.Pkt{tag: :authentication, payload: :authentication_ok} ->
          setup_finish(conn)

        unexpected ->
          {:error, {:unexpected_msg, unexpected}}
      end
    end
  end

  # Socket handling

  defp send_msg({mod, sock}, msg), do: mod.send(sock, msg)

  @header_size 5

  defp recv_msg(sock) do
    case recv_pkt(sock) do
      {:ok, %Server.Pkt{tag: log, payload: _}}
      when log in [:notification_response, :notice_response] ->
        recv_msg(sock)

      other ->
        other
    end
  end

  defp recv_pkt(sock) do
    with {:ok, <<code::8-integer, size::32-integer>>} <- recv(sock, @header_size) do
      case size - 4 do
        0 ->
          Server.decode_pkt(code, <<>>)

        len when len > 0 ->
          with {:ok, payload} <- recv(sock, len),
               do: Server.decode_pkt(code, payload)
      end
    end
  end

  defp recv({mod, sock}, len), do: mod.recv(sock, len)
end
