<!--
SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>

SPDX-License-Identifier: Apache-2.0
SPDX-License-Identifier: EUPL-1.2
-->

# Logs

Ultravisor will emit various logs during operation.

Use these error codes to debug a running Ultravisor cluster.

## Error Codes

| Code                      | Description                                                          |
| ------------------------- | -------------------------------------------------------------------- |
| `MaxClientsInSessionMode` | When in Session mode client connections are limited by the pool_size |
| `ListenerShutdownError` | There was an error during listener process shutdown                    |
