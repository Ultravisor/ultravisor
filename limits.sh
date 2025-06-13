#!/bin/bash

# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

if [ ! -z "$RLIMIT_NOFILE" ]; then
    echo "Setting RLIMIT_NOFILE to ${RLIMIT_NOFILE}"
    ulimit -n "$RLIMIT_NOFILE"
fi

exec "$@"
