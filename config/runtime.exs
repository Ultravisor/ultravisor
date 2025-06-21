# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

import Config

require Logger
alias Ultravisor.Helpers
alias Ultravisor.Config

config :ultravisor,
  metrics_enabled: Config.get_bool("ULTRAVISOR_METRICS"),
  metadata: Config.get_json("ULTRAVISOR_METADATA")

secret_key_base =
  if config_env() in [:dev, :test] do
    "3S1V5RyqQcuPrMVuR4BjH9XBayridj56JA0EE6wYidTEc6H84KSFY6urVX7GfOhK"
  else
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """
  end

config :ultravisor, UltravisorWeb.Endpoint,
  server: true,
  http: [
    port: Config.get_integer("ULTRAVISOR_MANAGEMENT_PORT", 4000),
    transport_options: [
      max_connections: Config.get_integer("ULTRAVISOR_HTTP_MAX_CONNECTIONS", 1000),
      num_acceptors: Config.get_integer("ULTRAVISOR_HTTP_NUM_ACCEPTORS", 100),
      socket_opts: [
        Config.get_enum("ULTRAVISOR_ADDR_TYPE", ~w[inet inet6]a, :inet)
      ]
    ]
  ],
  secret_key_base: secret_key_base

config :ultravisor, :cluster_channel, System.get_env("ULTRAVISOR_CLUSTER_POSTGRES")

config :libcluster,
  debug: false

upstream_ca =
  if path = System.get_env("GLOBAL_UPSTREAM_CA_PATH") do
    File.read!(path)
    |> Helpers.cert_to_bin()
    |> case do
      {:ok, bin} ->
        Logger.info("Loaded upstream CA from $GLOBAL_UPSTREAM_CA_PATH",
          ansi_color: :green
        )

        bin

      {:error, _} ->
        raise "There is no valid certificate in $GLOBAL_UPSTREAM_CA_PATH"
    end
  end

downstream_cert =
  if path = System.get_env("GLOBAL_DOWNSTREAM_CERT_PATH") do
    if File.exists?(path) do
      Logger.info("Loaded downstream cert from $GLOBAL_DOWNSTREAM_CERT_PATH, path: #{path}",
        ansi_color: :green
      )

      path
    else
      raise "There is no such file in $GLOBAL_DOWNSTREAM_CERT_PATH"
    end
  end

downstream_key =
  if path = System.get_env("GLOBAL_DOWNSTREAM_KEY_PATH") do
    if File.exists?(path) do
      Logger.info("Loaded downstream key from $GLOBAL_DOWNSTREAM_KEY_PATH, path: #{path}",
        ansi_color: :green
      )

      path
    else
      raise "There is no such file in $GLOBAL_DOWNSTREAM_KEY_PATH"
    end
  end

db_socket_options =
  if System.get_env("ULTRAVISOR_DB_IP_VERSION") == "ipv6",
    do: [:inet6],
    else: [:inet]

if config_env() != :test do
  config :ultravisor,
    availability_zone: System.get_env("AVAILABILITY_ZONE"),
    jwt_claim_validators: Config.get_json("JWT_CLAIM_VALIDATORS"),
    api_jwt_secret: System.get_env("API_JWT_SECRET"),
    metrics_jwt_secret: System.get_env("METRICS_JWT_SECRET"),
    proxy_port_transaction: Config.get_integer("PROXY_PORT_TRANSACTION", 6543),
    proxy_port_session: Config.get_integer("PROXY_PORT_SESSION", 5432),
    proxy_port: Config.get_integer("PROXY_PORT", 5412),
    prom_poll_rate: Config.get_integer("PROM_POLL_RATE", 15000),
    global_upstream_ca: upstream_ca,
    global_downstream_cert: downstream_cert,
    global_downstream_key: downstream_key,
    reconnect_on_db_close: Config.get_bool("RECONNECT_ON_DB_CLOSE"),
    api_blocklist: Config.get_list("API_TOKEN_BLOCKLIST"),
    metrics_blocklist: Config.get_list("METRICS_TOKEN_BLOCKLIST"),
    node_host: System.get_env("NODE_IP", "127.0.0.1"),
    local_proxy_multiplier: Config.get_integer("LOCAL_PROXY_MULTIPLIER", 20)

  config :ultravisor, Ultravisor.Repo,
    url: System.get_env("DATABASE_URL", "ecto://postgres:postgres@localhost:6432/postgres"),
    pool_size: Config.get_integer("DB_POOL_SIZE", 25),
    ssl_opts: [
      verify: :verify_none
    ],
    parameters: [
      application_name: "ultravisor_meta"
    ],
    socket_options: db_socket_options

  config :ultravisor, Ultravisor.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1", key: System.get_env("VAULT_ENC_KEY")
      }
    ]
end

if path = System.get_env("ULTRAVISOR_LOG_FILE_PATH") do
  config :logger, :default_handler,
    config: [
      file: to_charlist(path),
      file_check: 1000,
      max_no_files: 5,
      # 8 MiB as a max file size
      max_no_bytes: 8 * 1024 * 1024
    ]
end

if System.get_env("ULTRAVISOR_LOG_FORMAT") == "json" do
  config :logger, :default_handler,
    formatter:
      {Ultravisor.Logger.LogflareFormatter,
       %{
         # metadata: metadata,
         top_level: [:project],
         context: [:hostname]
       }}
end

if path = System.get_env("ULTRAVISOR_ACCESS_LOG_FILE_PATH") do
  config :ultravisor, :logger, [
    {:handler, :access_log, :logger_std_h,
     %{
       level: :error,
       formatter:
         Logger.Formatter.new(
           format: "$dateT$timeZ $metadata[$level] $message\n",
           color: false,
           metadata: [:peer_ip],
           utc_log: true
         ),
       filter_default: :stop,
       filters: [
         exchange: {&Ultravisor.Logger.Filters.filter_client_handler/2, :exchange}
       ],
       config: %{
         file: to_charlist(path),
         # Keep the file clean on each startup
         modes: [:write]
       }
     }}
  ]
end

config :logger,
  backends: [:console]
