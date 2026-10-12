# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

{
  pkgs,
  lib,
  config,
  ...
}:

let
  beam = pkgs.beam.packages.erlang_29;
in
{
  languages.elixir = {
    enable = true;
    package = beam.elixir_1_20;
  };

  languages.erlang = {
    enable = true;
    package = beam.erlang;
  };

  packages = [
    pkgs.pgbouncer
    pkgs.pgdog
    pkgs.xan

    pkgs.cargo-outdated
    pkgs.cargo-nextest
  ];

  services.postgres = {
    enable = true;
    package = pkgs.postgresql_18_jit;
    initialScript = ''
      ${builtins.readFile ./dev/postgres/00-setup.sql}

      CREATE USER postgres SUPERUSER PASSWORD 'postgres';
    '';
    listen_addresses = "127.0.0.1";
    port = 6432;
    settings = {
      max_prepared_transactions = 262143;
      random_page_cost = 1.1;
    };
  };

  processes.postgres = {
    ready = {
      exec = let
        postgresPkg = config.services.postgres.package;
      in lib.mkForce ''
        if [[ -f "$PGDATA/.devenv_initialized" ]]; then
          ${postgresPkg}/bin/pg_isready -d template1 && \\
            ${postgresPkg}/bin/psql -h localhost -c "SELECT 1" template1 > /dev/null 2>&1
        else
          echo "Waiting for PostgreSQL initialization to complete..." 2>&1
            exit 1
            fi
            '';
      initial_delay = 2;
      probe_timeout = 4;
      failure_threshold = 5;
    };
  };

  process.manager.implementation = "honcho";

# Force connection through TCP instead of Unix socket
  env.PGHOST = lib.mkForce "";

  env.MIMALLOC = "${pkgs.mimalloc}";
  env.JEMALLOC = "${pkgs.jemalloc}";
  env.SNMALLOC = "${pkgs.snmalloc}";

  languages.deno.enable = true;

  languages.javascript = {
    enable = true;
    bun.enable = true;
    yarn.enable = true;
  };

  languages.rust.enable = true;
}
