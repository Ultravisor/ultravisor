<!--
SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>

SPDX-License-Identifier: Apache-2.0
SPDX-License-Identifier: EUPL-1.2
-->

# Installation

Before starting, set up the database where Ultravisor will store tenants' data.
The following command will pull a Docker image with PostgreSQL 14 and run it on
port 6432:

```
docker-compose -f ./docker-compose.db.yml up
```

> `Ultravisor` stores tables in the `ultravisor` schema. The schema should be
> automatically created by the `dev/postgres/00-setup.sql` file. If you
> encounter issues with migrations, ensure that this schema exists.

Next, get dependencies and apply migrations:

```
mix deps.get && mix ecto.migrate --prefix _ultravisor --log-migrator-sql
```
