-- SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
-- SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
--
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-License-Identifier: EUPL-1.2

create role anon          nologin noinherit;
create role authenticated nologin noinherit;
create role service_role  nologin noinherit bypassrls;

grant usage on schema public to anon, authenticated, service_role;

alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

create schema if not exists _ultravisor;
