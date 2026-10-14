# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2
{
  description = "Elixir's application";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      flake = { };

      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        { self', pkgs, ... }:
        {
          formatter = pkgs.nixfmt-tree;

          packages = {
            ultravisor =
              let
                erl = pkgs.beam.packages.erlang_29;
              in
              erl.callPackage ./nix/package.nix { };

            default = self'.packages.ultravisor;
          };
        };
    };
}
