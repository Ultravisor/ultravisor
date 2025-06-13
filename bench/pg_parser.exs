# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

alias Supavisor.PgParser, as: Parser

Benchee.run(%{
  "statement_types/1" => fn ->
    Parser.statement_types("insert into table1 values ('a', 'b')")
  end
})
