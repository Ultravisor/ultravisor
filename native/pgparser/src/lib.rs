// SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
// SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
//
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: EUPL-1.2

#[rustler::nif]
fn statement_types(query: &str) -> Result<Vec<String>, String> {
    let result = pg_query::parse(query).map_err(|_| "Error parsing query")?;

    let message = result
        .statement_types()
        .into_iter()
        .map(Into::into)
        .collect();
    Ok(message)
}

rustler::init!("Elixir.Ultravisor.PgParser");
