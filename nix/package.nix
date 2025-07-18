# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

{
  fetchMixDeps,
  mixRelease,
  cargo,
  rustPlatform,
  lib,
  stdenv,
  darwin,
  protobuf,
  libiconv,
}: let
  pname = "ultravisor";
  version = "0.0.1";
  src = ./..;

  mixFodDeps = fetchMixDeps {
    pname = "mix-deps-${pname}";
    inherit src version;
    hash = "sha256-vTBDNIZ6Pp23u70f8oTe3nbpReCEDPf6VuWNLdkWwq4=";
  };

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ../native/pgparser/Cargo.lock;
  };
in
  mixRelease {
    inherit pname version src mixFodDeps;

    nativeBuildInputs = [cargo protobuf];

    buildInputs = lib.optionals stdenv.isDarwin (with darwin.apple_sdk; [
      libiconv
      frameworks.System
      frameworks.CoreFoundation
      frameworks.CoreServices
      frameworks.DiskArbitration
      frameworks.IOKit
      frameworks.CFNetwork
      frameworks.Security
      libs.libDER
    ]);

    preConfigure = ''
      cat ${cargoDeps}/.cargo/config >> native/pgparser/.cargo/config.toml
      ln -s ${cargoDeps} native/pgparser/cargo-vendor-dir
    '';

    meta = {
      mainProgram = "ultravisor";
    };
  }
