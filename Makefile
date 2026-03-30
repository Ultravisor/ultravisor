# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

# Display this help
help:
	@mix make_help $(MAKEFILE_LIST)

node_id ?= 0

.PHONY: dev db_migrate clean
# Start new development instance
#
# Arguments:
#   node_id (default: 0) - positive number marking node ID
dev:
	ERL_AFLAGS="+zdbbl 2097151" \
	iex -S mix dev --node ${node_id}

db_migrate:
	mix ecto.migrate --prefix _ultravisor --log-migrator-sql

# Cleanup work environment
clean:
	mix clean && rm -rf _build deps target priv/native/

## Benchmarking

host ?= localhost
user ?= postgres.sys
port ?= 6543
duration ?= 60
clients ?= 32
protocol ?= extended

.PHONY: pgbench.init pgbench pgbouncer pgdog
psql:
	PGPASSWORD=postgres psql postgres://${user}@${host}:${port}/postgres?sslmode=disable

# Initialise PgBench database
pgbench.init:
	PGPASSWORD=postgres pgbench -i -h localhost -p 6432 -U postgres -d postgres

# Run PgBench
#
# Arguments:
#   host (default: localhost) - host on which SUT is running
#   user (default: postgres.sys) - user which will be used to connect to DB
#   port (default: 6543) - port on which SUT is running
#   duration (default: 60) - overall duration of test in seconds
#   clients (default: 32) - number of client connections used during test
#   protocol (default: extended) - protocol kind used during tests
pgbench:
	PGPASSWORD="postgres" pgbench \
		   postgres://${user}@${host}:${port}/postgres?sslmode=disable \
		   --select-only \
		   --report-per-command \
		   --no-vacuum \
		   --time ${duration} \
		   --jobs=4 \
		   --client=${clients} \
		   --progress=10 \
		   --protocol=${protocol}

# Run PgBouncer instance to compare benchmarks
pgbouncer:
	cd $(PWD)/bench/pgbouncer && \
		pgbouncer pgbouncer.conf

# Run PgDog instance to compare benchmarks
pgdog:
	pgdog \
		--config $(PWD)/bench/pgdog/config.toml \
		--users  $(PWD)/bench/pgdog/users.toml

dev_release:
	mix deps.get && mix compile && mix release ultravisor

dev_up:
	rm -rf _build/dev/lib/ultravisor && \
	MIX_ENV=dev mix compile && \
	mix release ultravisor

dev_start_rel:
	MIX_ENV=dev \
	VAULT_ENC_KEY="aHD8DZRdk2emnkdktFZRh3E9RNg4aOY7" \
	API_JWT_SECRET=dev \
	METRICS_JWT_SECRET=dev \
	SECRET_KEY_BASE="dev" \
	ULTRAVISOR_CLUSTER_POSTGRES="ultravisor_local" \
	DB_POOL_SIZE="5" \
	_build/prod/rel/ultravisor/bin/ultravisor start_iex

prod_rel:
	MIX_ENV=prod mix compile && \
	MIX_ENV=prod mix release ultravisor

prod_start_rel:
	MIX_ENV=prod \
	NODE_NAME="localhost" \
	VAULT_ENC_KEY="aHD8DZRdk2emnkdktFZRh3E9RNg4aOY7" \
	API_JWT_SECRET=dev \
	METRICS_JWT_SECRET=dev \
	SECRET_KEY_BASE="dev" \
	ULTRAVISOR_CLUSTER_POSTGRES="ultravisor_local" \
	DB_POOL_SIZE="5" \
	_build/prod/rel/ultravisor/bin/ultravisor start_iex

prod_start_rel2:
	MIX_ENV=prod \
	NODE_NAME=node2 \
	ULTRAVISOR_MANAGEMENT_PORT=4001 \
	VAULT_ENC_KEY="aHD8DZRdk2emnkdktFZRh3E9RNg4aOY7" \
	API_JWT_SECRET=dev \
	METRICS_JWT_SECRET=dev \
	SECRET_KEY_BASE="dev" \
	ULTRAVISOR_CLUSTER_POSTGRES="ultravisor_local" \
	PROXY_PORT_SESSION="5442" \
	PROXY_PORT_TRANSACTION="6553" \
	NODE_IP=localhost \
	_build/prod/rel/ultravisor/bin/ultravisor start_iex
