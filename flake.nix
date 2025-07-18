# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

{
  description = "Elixir's application";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  inputs.devenv = {
    url = "github:cachix/devenv";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    flake-parts,
    devenv,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      flake = {};

      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem = {
        self',
        inputs',
        pkgs,
        lib,
        ...
      }: {
        formatter = pkgs.alejandra;

        packages = {
          # Expose Devenv supervisor
          devenv-up = self'.devShells.default.config.procfileScript;

          ultravisor = let
            erl = pkgs.beam_nox.packages.erlang_27;
          in
            erl.callPackage ./nix/package.nix {};

          default = self'.packages.ultravisor;
        };

        devShells.default = devenv.lib.mkShell {
          inherit inputs pkgs;

          modules = [
            {
              git-hooks.hooks = {
                alejandra.enable = true;
                typos = {
                  enable = true;
                  excludes = [
                    "test/integration/"
                  ];
                };
                check-yaml.enable = true;
                # yamlfmt.enable = true;
              };
            }
            {
              languages.elixir = {
                enable = true;
                package = pkgs.beam.packages.erlang_27.elixir_1_18;
              };
              packages = [
                pkgs.lexical
              ];

              git-hooks.hooks = {
                mix-format.enable = true;
                # credo.enable = true;
              };

              # env.DYLD_INSERT_LIBRARIES = "${pkgs.mimalloc}/lib/libmimalloc.dylib";
            }
            {
              packages = [
                pkgs.pgbouncer
              ];

              services.postgres = {
                enable = true;
                package = pkgs.postgresql_15;
                initialScript = ''
                  ${builtins.readFile ./dev/postgres/00-setup.sql}

                  CREATE USER postgres SUPERUSER PASSWORD 'postgres';
                '';
                listen_addresses = "127.0.0.1";
                port = 6432;
                settings = {
                  max_prepared_transactions = 262143;
                };
              };

              process.manager.implementation = "honcho";

              # Force connection through TCP instead of Unix socket
              env.PGHOST = lib.mkForce "";

              # env.DATABASE_URL = "postgres://postgres:postgres@localhost:6432/";
            }
            {
              languages.javascript = {
                enable = true;
                bun.enable = true;
                yarn.enable = true;
              };
            }
            ({
              pkgs,
              ...
            }: {
              languages.cplusplus.enable = true;

              packages =
                [
                  pkgs.prom2json
                ];
            })
          ];
        };
      };
    };
}
