# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

alias Ultravisor.PgParser, as: Parser

Benchee.run(%{
  "statement_types/1" => fn ->
    Parser.statement_types("insert into table1 values ('a', 'b')")
  end
})
