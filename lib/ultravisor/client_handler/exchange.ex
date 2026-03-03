# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.ClientHandler.Exchange do
  require Logger
  require Ultravisor.Protocol.Server, as: Server

  alias Ultravisor.HandlerHelpers
  alias Ultravisor.Helpers
  alias Ultravisor.Tenants
  alias Ultravisor.Protocol.Errors

  import Ultravisor, only: [conn_id: 1]
  import Ultravisor.ClientHandler, only: [data: 1, data: 2]

  def handle({_proto, _, <<"GET">> <> _}, _data),
    do: {:error, :http_request}

  def handle({_, _, bin}, _) when byte_size(bin) > 1024,
    do: {:error, :startup_packet_too_large}

  def handle({:tcp, _, Server.ssl_request()}, data(sock: sock)) do
    Logger.debug("ClientHandler: Client is trying to connect with SSL")

    downstream_cert = Helpers.downstream_cert()
    downstream_key = Helpers.downstream_key()

    # SSL negotiation, S/N/Error
    if !!downstream_cert and !!downstream_key do
      :ok = HandlerHelpers.setopts(sock, active: false)
      :ok = HandlerHelpers.sock_send(sock, "S")

      opts = [
        verify: :verify_none,
        certfile: downstream_cert,
        keyfile: downstream_key
      ]

      case :ssl.handshake(elem(sock, 1), opts) do
        {:ok, ssl_sock} ->
          {:upgrade, {:ssl, ssl_sock}}

        {:error, reason} ->
          {:error, {:ssl_handshake_error, reason}}
      end
    else
      {:no_upgrade, sock}
    end
  end

  def handle({_proto, _sock, bin}, data) do
    case Server.decode_startup_packet(bin) do
      {:ok, hello} ->
        Logger.debug("ClientHandler: Client startup message: #{inspect(hello)}")
        {type, {user, tenant_or_alias, db_name}} = HandlerHelpers.parse_user_info(hello.payload)

        if Helpers.valid_name?(user) and Helpers.valid_name?(db_name) do
          log_level = maybe_change_log(hello)
          search_path = hello.payload["options"]["--search_path"]
          app_name = app_name(hello.payload["application_name"])

          hello(
            type,
            user,
            tenant_or_alias,
            db_name,
            search_path,
            data(data, log_level: log_level, app_name: app_name)
          )
        else
          {:error, %Errors.InvalidFormatError{user: user, db_name: db_name}, data}
        end

      {:error, error} ->
        {:error, {:startup_packet_error, error}, data}
    end
  end

  defp hello(
         type,
         user,
         tenant_or_alias,
         db_name,
         search_path,
         data(sock: sock) = data
       ) do
    sni_hostname = HandlerHelpers.try_get_sni(sock)

    case Tenants.get_user_cache(type, user, tenant_or_alias, sni_hostname) do
      {:ok, info} ->
        db_name = db_name || info.tenant.db_database

        id =
          conn_id(
            type: type,
            tenant: tenant_or_alias,
            user: user,
            mode: data(data, :mode),
            db_name: db_name,
            search_path: search_path
          )

        mode = Ultravisor.mode(id)

        Logger.metadata(
          project: tenant_or_alias,
          user: user,
          mode: mode,
          type: type,
          db_name: db_name,
          app_name: data(data, :app_name)
        )

        {:ok, addr} = HandlerHelpers.addr_from_sock(sock)

        cond do
          not data(data, :local) and info.tenant.enforce_ssl and not data(data, :ssl) ->
            {:error, :ssl_required, data}

          HandlerHelpers.filter_cidrs(info.tenant.allow_list, addr) == [] ->
            {:error, :address_not_allowed, data}

          true ->
            new_data = update_user_data(data, info, user, id, db_name, mode)

            key = {:secrets, tenant_or_alias, user}

            case auth_secrets(info, user, key, :timer.hours(24)) do
              {:ok, auth_secrets} ->
                auth(auth_secrets, info, new_data)

              {:error, reason} ->
                {:error, {:auth_secrets_error, reason}, data}
            end
        end

      {:error, reason} ->
        {:error, {:user_not_found, reason}, data}
    end
  end

  defp auth({method, secrets}, info, data(id: id, sock: sock) = data) do
    Logger.debug("ClientHandler: Handle exchange, auth method: #{inspect(method)}")

    case handle_exchange(sock, {method, secrets}) do
      {:error, reason} ->
        Logger.error(
          "ClientHandler: Exchange error: #{inspect(reason)} when method #{inspect(method)}"
        )

        msg =
          if method == :auth_query_md5,
            do: Server.error_message("XX000", reason),
            else: Server.exchange_message(:final, "e=#{reason}")

        conn_id(tenant: tenant, user: user) = id

        key = {:secrets_check, tenant, user}

        if method != :password and reason == "Wrong password" and
             Cachex.get(Ultravisor.Cache, key) == {:ok, nil} do
          case auth_secrets(info, user, key, 15_000) do
            {:ok, {method2, secrets2}} = value ->
              if method != method2 or Map.delete(secrets.(), :client_key) != secrets2.() do
                Logger.warning("ClientHandler: Update secrets and terminate pool")

                Cachex.update(
                  Ultravisor.Cache,
                  {:secrets, tenant, user},
                  {:cached, value}
                )

                Ultravisor.stop(id)
              else
                Logger.debug("ClientHandler: Cache the same #{inspect(key)}")
              end

            other ->
              Logger.error("ClientHandler: Auth secrets check error: #{inspect(other)}")
          end
        else
          Logger.debug("ClientHandler: Cache hit for #{inspect(key)}")
        end

        HandlerHelpers.sock_send(sock, msg)
        {:error, :exchange_error, data}

      {:ok, client_key} ->
        secrets =
          if client_key,
            do: fn -> Map.put(secrets.(), :client_key, client_key) end,
            else: secrets

        Logger.debug("ClientHandler: Exchange success")

        auth = Map.merge(data(data, :auth), %{secrets: secrets, method: method})

        conn_type =
          if data(data, :mode) == :proxy,
            do: :connect_db,
            else: {:subscribe, 0}

        {:ok, conn_type, data(data, auth_secrets: {method, secrets}, auth: auth)}
    end
  end

  @spec auth_secrets(map, String.t(), term(), non_neg_integer()) ::
          {:ok, Ultravisor.secrets()} | {:error, term()}
  ## password secrets
  defp auth_secrets(%{user: user, tenant: %{require_user: true}}, _, _, _) do
    secrets = %{db_user: user.db_user, password: user.db_password, alias: user.db_user_alias}

    {:ok, {:password, fn -> secrets end}}
  end

  ## auth_query secrets
  defp auth_secrets(info, db_user, key, ttl) do
    fetch = fn _key ->
      case get_secrets(info, db_user) do
        {:ok, _} = resp -> {:commit, {:cached, resp}, expire: ttl}
        {:error, _} = resp -> {:ignore, resp}
      end
    end

    case Cachex.fetch(Ultravisor.Cache, key, fetch) do
      {:ok, {:cached, value}} -> value
      {:commit, {:cached, value}} -> value
      {:ignore, resp} -> resp
    end
  end

  @spec get_secrets(map, String.t()) :: {:ok, {:auth_query, fun()}} | {:error, term()}
  defp get_secrets(%{user: user, tenant: tenant}, db_user) do
    ssl_opts =
      if tenant.upstream_ssl and tenant.upstream_verify == :peer do
        [
          verify: :verify_peer,
          cacerts: [Helpers.upstream_cert(tenant.upstream_tls_ca)],
          server_name_indication: String.to_charlist(tenant.db_host),
          customize_hostname_check: [{:match_fun, fn _, _ -> true end}]
        ]
      else
        [
          verify: :verify_none
        ]
      end

    {:ok, conn} =
      Postgrex.start_link(
        hostname: tenant.db_host,
        port: tenant.db_port,
        database: tenant.db_database,
        password: user.db_password,
        username: user.db_user,
        parameters: [application_name: "Ultravisor auth_query"],
        ssl: tenant.upstream_ssl,
        socket_options: [
          Helpers.ip_version(tenant.ip_version, tenant.db_host)
        ],
        queue_target: 1_000,
        queue_interval: 5_000,
        ssl_opts: ssl_opts
      )

    try do
      Logger.debug(
        "ClientHandler: Connected to db #{tenant.db_host} #{tenant.db_port} #{tenant.db_database} #{user.db_user}"
      )

      resp =
        with {:ok, secret} <- Helpers.get_user_secret(conn, tenant.auth_query, db_user) do
          t = if secret.digest == :md5, do: :auth_query_md5, else: :auth_query
          {:ok, {t, fn -> Map.put(secret, :alias, user.db_user_alias) end}}
        end

      Logger.info("ClientHandler: Get secrets finished")
      resp
    rescue
      exception ->
        Logger.error("ClientHandler: Couldn't fetch user secrets from #{tenant.db_host}")
        reraise exception, __STACKTRACE__
    after
      GenServer.stop(conn, :normal, 5_000)
    end
  end

  @spec app_name(any()) :: String.t()
  defp app_name(name) when is_binary(name), do: name

  defp app_name(nil), do: "Ultravisor"

  defp app_name(name) do
    Logger.debug("ClientHandler: Invalid application name #{inspect(name)}")
    "Ultravisor"
  end

  @spec maybe_change_log(map()) :: atom() | nil
  defp maybe_change_log(%{"payload" => %{"options" => options}}) do
    level = options["log_level"] && String.to_existing_atom(options["log_level"])

    if level in [:debug, :info, :notice, :warning, :error] do
      Helpers.set_log_level(level)
      level
    end
  end

  defp maybe_change_log(_), do: :ok

  @spec handle_exchange(Ultravisor.sock(), {atom(), fun()}) ::
          {:ok, binary() | nil} | {:error, String.t()}
  defp handle_exchange(sock, {:auth_query_md5 = method, secrets}) do
    salt = :crypto.strong_rand_bytes(4)
    :ok = HandlerHelpers.sock_send(sock, Server.md5_request(salt))

    with {:ok,
          %{
            tag: :password_message,
            payload: {:md5, client_md5}
          }, _} <- receive_next(sock, "Timeout while waiting for the md5 exchange"),
         {:ok, key} <- authenticate_exchange(method, client_md5, secrets.().secret, salt) do
      {:ok, key}
    else
      {:error, message} -> {:error, message}
      other -> {:error, "Unexpected message #{inspect(other)}"}
    end
  end

  defp handle_exchange(sock, {method, secrets}) do
    :ok = HandlerHelpers.sock_send(sock, Server.scram_request())

    with {:ok,
          %{
            tag: :password_message,
            payload: {:scram_sha_256, %{"n" => user, "r" => nonce, "c" => channel}}
          }, _} <-
           receive_next(
             sock,
             "Timeout while waiting for the first password message"
           ),
         {:ok, signatures} = reply_first_exchange(sock, method, secrets, channel, nonce, user),
         {:ok,
          %{
            tag: :password_message,
            payload: {:first_msg_response, %{"p" => p}}
          }, _} <-
           receive_next(
             sock,
             "Timeout while waiting for the second password message"
           ),
         {:ok, key} <- authenticate_exchange(method, secrets, signatures, p) do
      message = "v=#{Base.encode64(signatures.server)}"
      :ok = HandlerHelpers.sock_send(sock, Server.exchange_message(:final, message))
      {:ok, key}
    else
      {:error, message} -> {:error, message}
      other -> {:error, "Unexpected message #{inspect(other)}"}
    end
  end

  defp update_user_data(data, info, user, id, db_name, mode) do
    auth = %{
      application_name: data(data, :app_name) || "Ultravisor",
      database: db_name,
      host: to_charlist(info.tenant.db_host),
      sni_hostname:
        if(info.tenant.sni_hostname != nil, do: to_charlist(info.tenant.sni_hostname)),
      port: info.tenant.db_port,
      user: user,
      password: info.user.db_password,
      require_user: info.tenant.require_user,
      upstream_ssl: info.tenant.upstream_ssl,
      upstream_tls_ca: info.tenant.upstream_tls_ca,
      upstream_verify: info.tenant.upstream_verify
    }

    data(data,
      timeout: info.user.pool_checkout_timeout,
      ps: info.tenant.default_parameter_status,
      id: id,
      heartbeat_interval: info.tenant.client_heartbeat_interval * 1000,
      mode: mode,
      auth: auth,
      tenant_availability_zone: info.tenant.availability_zone
    )
  end

  defp authenticate_exchange(:password, _secrets, signatures, p) do
    if p == signatures.client,
      do: {:ok, nil},
      else: {:error, "Wrong password"}
  end

  defp authenticate_exchange(:auth_query, secrets, signatures, p) do
    client_key = :crypto.exor(Base.decode64!(p), signatures.client)

    if Helpers.hash(client_key) == secrets.().stored_key do
      {:ok, client_key}
    else
      {:error, "Wrong password"}
    end
  end

  defp authenticate_exchange(:auth_query_md5, client_hash, server_hash, salt) do
    if "md5" <> Helpers.md5([server_hash, salt]) == client_hash,
      do: {:ok, nil},
      else: {:error, "Wrong password"}
  end

  defp receive_next({mod, socket}, timeout_message) do
    case mod.recv(socket, 0, 15_000) do
      {:ok, bin} -> Server.decode_pkt(bin)
      {:error, :timeout} -> {:error, timeout_message}
      {:error, other} -> {:error, "Unexpected message in receive_next/2 #{inspect(other)}"}
    end
  end

  defp reply_first_exchange(sock, method, secrets, channel, nonce, user) do
    {message, signatures} = exchange_first(method, secrets, nonce, user, channel)
    :ok = HandlerHelpers.sock_send(sock, Server.exchange_message(:first, message))
    {:ok, signatures}
  end

  @spec exchange_first(:password | :auth_query, fun(), binary(), binary(), binary()) ::
          {binary(), map()}
  defp exchange_first(:password, secret, nonce, user, channel) do
    message = Server.exchange_first_message(nonce)
    server_first_parts = Helpers.parse_server_first(message, nonce)

    {client_final_message, server_proof} =
      Helpers.get_client_final(
        :password,
        secret.().password,
        server_first_parts,
        nonce,
        user,
        channel
      )

    sings = %{
      client: List.last(client_final_message),
      server: server_proof
    }

    {message, sings}
  end

  defp exchange_first(:auth_query, secret, nonce, user, channel) do
    secret = secret.()
    message = Server.exchange_first_message(nonce, secret.salt)
    server_first_parts = Helpers.parse_server_first(message, nonce)

    sings =
      Helpers.signatures(
        secret.stored_key,
        secret.server_key,
        server_first_parts,
        nonce,
        user,
        channel
      )

    {message, sings}
  end
end
