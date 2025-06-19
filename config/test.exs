# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

import Config

config :ultravisor,
  region: "eu",
  api_jwt_secret: "api-test-secret",
  metrics_jwt_secret: "metrics-test-secret",
  jwt_claim_validators: %{},
  proxy_port_session: System.get_env("PROXY_PORT_SESSION", "7653") |> String.to_integer(),
  proxy_port_transaction: System.get_env("PROXY_PORT_TRANSACTION", "7654") |> String.to_integer(),
  proxy_port: System.get_env("PROXY_PORT", "5412") |> String.to_integer(),
  secondary_proxy_port: 7655,
  secondary_http: 4003,
  prom_poll_rate: 500,
  api_blocklist: [
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJibG9ja2VkIiwiaWF0IjoxNjQ1MTkyODI0LCJleHAiOjE5NjA3Njg4MjR9.y-V3D1N2e8UTXc5PJzmV9cqMteq0ph2wl0yt42akQgA"
  ],
  metrics_blocklist: [],
  node_host: System.get_env("NODE_IP", "127.0.0.1"),
  availability_zone: System.get_env("AVAILABILITY_ZONE"),
  max_pools: 5,
  reconnect_retries: System.get_env("RECONNECT_RETRIES", "5") |> String.to_integer(),
  subscribe_retries: System.get_env("SUBSCRIBE_RETRIES", "5") |> String.to_integer(),
  local_proxy_multiplier: System.get_env("LOCAL_PROXY_MULTIPLIER", "20") |> String.to_integer()

config :ultravisor, Ultravisor.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ultravisor_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  port: 6432

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ultravisor, UltravisorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false

config :ultravisor, Ultravisor.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1", key: "aHD8DZRdk2emnkdktFZRh3E9RNg4aOY7"
    }
  ]

# Print only warnings and errors during test
config :logger, :default_handler, level: String.to_atom(System.get_env("LOGGER_LEVEL", "none"))

config :logger, :default_formatter,
  metadata: [:error_code, :file, :line, :pid, :project, :user, :mode]

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
