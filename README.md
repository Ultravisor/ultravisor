<!--
SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>

SPDX-License-Identifier: Apache-2.0
SPDX-License-Identifier: EUPL-1.2
-->

# Ultravisor - Postgres connection pooler

- [Overview](#overview)
- [Motivation](#motivation)
- [Architecture](#architecture)
- [Docs](#docs)
- [Features](#features)
- [Future work](#future-work)
- [Acknowledgements](#acknowledgements)
- [Benchmarks](#benchmarks)
- [Inspiration](#inspiration)

## Overview

Ultravisor is a scalable, cloud-native Postgres connection pooler. A Ultravisor
cluster is capable of proxying millions of Postgres end-client connections into
a stateful pool of native Postgres database connections.

For database managers, Ultravisor simplifies the task of managing Postgres
clusters by providing easy configuration of highly available Postgres clusters
([todo](#future-work)).

## Motivation

We have several goals with Ultravisor:

- **Zero-downtime scaling**: we want to scale Postgres server compute with
  zero-downtime. To do this, we need an external Pooler that can buffer and
  re-route requests while the resizing operation is in progress.
- **Handling modern connection demands**: We need a Pooler that can absorb
  millions of connections. We often see developers connecting to Postgres from
  Serverless environments, and so we also need something that works with both TCP
  and HTTP protocols.
- **Efficiency**: Our customers pay for database processing power, and our goal
  is to maximize their database capacity. While PgBouncer is resource-efficient,
  it still consumes some resources on the database instance. By moving connection
  pooling to a dedicated cluster adjacent to tenant databases, we can free up
  additional resources to better serve customer queries.

## Architecture

Ultravisor was designed to work in a cloud computing environment as a highly
available cluster of nodes. Tenant configuration is stored in a highly available
Postgres database. Configuration is loaded from the Ultravisor database when a
tenant connection pool is initiated.

Connection pools are dynamic. When a tenant client connects to the Ultravisor
cluster the tenant pool is started and all connections to the tenant database
are established. The process ID of the new tenant pool is then distributed to
all nodes of the cluster and stored in an in-memory key-value store. Subsequent
tenant client connections live on the inbound node but connection data is
proxied from the pool node to the client connection node as needed.

Because the count of Postgres connections is constrained only one tenant
connection pool should be alive in a Ultravisor cluster. In the case of two
simultaneous client connections starting a pool, as the pool process IDs are
distributed across the cluster, eventually one of those pools is gracefully
shutdown.

The dynamic nature of tenant database connection pools enables high availability
in the event of node outages. Pool processes are monitored by each node. If a
node goes down that process ID is removed from the cluster. Tenant clients will
then start a new pool automatically as they reconnect to the cluster.

This design enables blue-green or rolling deployments as upgrades require. A
single VPC / multiple availability zone topologies is possible and can provide
for greater redundancy when load balancing queries across read replicas are
supported ([todo](#future-work)).

## Docs

- [Installation and usage](https://ultravisor.github.io/ultravisor/development/installation/)
- [Metrics](https://ultravisor.github.io/ultravisor/monitoring/metrics/)

## Features

- Fast
  - Within 90% throughput as compared to `PgBouncer` running `pgbench` locally
- Scalable
  - 1 million Postgres connections on a cluster
  - 250_000 idle connections on a single 16 core node with 64GB of ram
- Multi-tenant
  - Connect to multiple different Postgres instances/clusters
- Single-tenant
  - Easy drop-in replacement for `PgBouncer`
- Pool mode support per tenant
  - Transaction
  - Session
- Cloud-native
  - Cluster-able
  - Resilient during cluster resizing
  - Supports rolling and blue/green deployment strategies
  - NOT run in a serverless environment
  - NOT dependant on Kubernetes
- Observable
  - Easily understand throughput by tenant, tenant database or individual
    connection
  - Prometheus `/metrics` endpoint
- Manageable
  - OpenAPI spec at `/api/openapi`
  - SwaggerUI at `/swaggerui`
- Highly available
  - When deployed as a Ultravisor cluster and a node dies connection pools should
    be quickly spun up or already available on other nodes when clients reconnect
- Connection buffering
  - Brief connection buffering for transparent database restarts or failovers

## Future Work

- Multi-protocol Postgres query interface
  - Postgres binary
  - HTTPS
  - Websocket
- Postgres high-availability management
  - Primary database election on primary failure
  - Health checks
  - Push button read-replica configuration
- Config as code
  - Not only for the Ultravisor cluster but tenant databases and tenant database
    clusters as well
  - Pulumi / Terraform support

## Acknowledgements

[José Valim](https://github.com/josevalim) and the [Dashbit](https://dashbit.co/) team were incredibly helpful in informing
the design decisions for Supavisor.

## Inspiration

- [PgBouncer](https://www.pgbouncer.org/)
- [stolon](https://github.com/sorintlab/stolon)
- [pgcat](https://github.com/levkk/pgcat)
- [odyssey](https://github.com/yandex/odyssey)
- [crunchy-proxy](https://github.com/CrunchyData/crunchy-proxy)
- [pgpool](https://www.pgpool.net/mediawiki/index.php/Main_Page)
- [pgagroal](https://github.com/agroal/pgagroal)

## Commercial Inspiration

- [proxysql.com](https://proxysql.com/)
- [Amazon RDS Proxy](https://aws.amazon.com/rds/proxy/)
- [Google Cloud SQL Proxy](https://github.com/GoogleCloudPlatform/cloud-sql-proxy)

## License

The project is for of Supabase's Supavisor, as so the licensing is:

Till commit `d7c2febd` (inclusive) - Apache-2.0 
Since commit `e82f1bc7` (inclusive) - EUPL-1.2
