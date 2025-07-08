# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

help:
	@make -qpRr | egrep -e '^[a-z].*:$$' | sed -e 's~:~~g' | sort

.PHONY: dev
dev:
	MIX_ENV=dev \
	VAULT_ENC_KEY="aHD8DZRdk2emnkdktFZRh3E9RNg4aOY7" \
	API_JWT_SECRET=dev \
	METRICS_JWT_SECRET=dev \
	SECRET_KEY_BASE="dev" \
	ULTRAVISOR_CLUSTER_POSTGRES="ultravisor_local" \
	DB_POOL_SIZE="5" \
	METRICS_DISABLED="false" \
	AVAILABILITY_ZONE="ap-southeast-1b" \
	ERL_AFLAGS="-kernel shell_history enabled +zdbbl 2097151" \
	iex --name node1@127.0.0.1 --cookie cookie -S mix run --no-halt

dev.node2:
	ULTRAVISOR_MANAGEMENT_PORT=4001 \
	MIX_ENV=dev \
	VAULT_ENC_KEY="aHD8DZRdk2emnkdktFZRh3E9RNg4aOY7" \
	API_JWT_SECRET=dev \
	METRICS_JWT_SECRET=dev \
	SECRET_KEY_BASE="dev" \
	ULTRAVISOR_CLUSTER_POSTGRES="ultravisor_local" \
	PROXY_PORT_SESSION="5442" \
	PROXY_PORT_TRANSACTION="6553" \
	PROXY_PORT="5402" \
	NODE_IP=localhost \
	AVAILABILITY_ZONE="ap-southeast-1c" \
	ERL_AFLAGS="-kernel shell_history enabled" \
	iex --name node2@127.0.0.1 --cookie cookie -S mix phx.server

dev.node3:
	ULTRAVISOR_MANAGEMENT_PORT=4002 \
	MIX_ENV=dev \
	VAULT_ENC_KEY="aHD8DZRdk2emnkdktFZRh3E9RNg4aOY7" \
	API_JWT_SECRET=dev \
	METRICS_JWT_SECRET=dev \
	SECRET_KEY_BASE="dev" \
	ULTRAVISOR_CLUSTER_POSTGRES="ultravisor_local" \
	PROXY_PORT_SESSION="5443" \
	PROXY_PORT_TRANSACTION="6554" \
	ERL_AFLAGS="-kernel shell_history enabled" \
	iex --name node3@127.0.0.1 --cookie cookie -S mix phx.server

db_migrate:
	mix ecto.migrate --prefix _ultravisor --log-migrator-sql

db_start:
	docker-compose -f ./docker-compose.db.yml up

db_stop:
	docker-compose -f ./docker-compose.db.yml down --remove-orphans

db_rebuild:
	make db_stop
	docker-compose -f ./docker-compose.db.yml build
	make db_start

user ?= postgres.sys
port ?= 6543
duration ?= 60
clients ?= 32
protocol ?= extended

pgbench_init:
	PGPASSWORD=postgres pgbench -i -h localhost -p 6432 -U postgres -d postgres

pgbench:
	PGPASSWORD="postgres" pgbench \
		   postgres://${user}@localhost:${port}/postgres?sslmode=disable \
		   --select-only \
		   --report-per-command \
		   --no-vacuum \
		   --time ${duration} \
		   --jobs=4 \
		   --client=${clients} \
		   --progress=10 \
		   --protocol=${protocol}

pgbouncer:
	cd $(PWD)/bench/pgbouncer && \
		pgbouncer pgbouncer.conf

clean:
	rm -rf _build && rm -rf deps

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
