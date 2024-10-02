{
  description = "A devShell example";

  inputs = {
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    haskellNix.url = "github:input-output-hk/haskell.nix";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url  = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, rust-overlay, haskellNix, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system overlays;
          inherit (haskellNix) config;
        };
        flake = pkgs.test-lurk-hs.flake {
        };
        overlays = [
          (import rust-overlay)
          (final: prev: {
            # jww (2024-09-17): This `mkShell'` override is needed to avoid a
            # linking problem that only occurs on Intel macOS:
            # ```
            # Undefined symbols for architecture x86_64: "_SecTrustEvaluateWithError"
            # ```
            mkShell = with prev; prev.mkShell.override {
              stdenv = if stdenv.isDarwin then overrideSDK stdenv "11.0" else stdenv;
            };
          })
          haskellNix.overlay
          (final: prev: {
            test-lurk-hs =
              final.haskell-nix.project' {
                src = ./.;
                supportHpack = true;
                compiler-nix-name = "ghc910";
                shell = {
                  tools = {
                    cabal = {};
                    haskell-language-server = {};
                    ghcid = {};
                  };
                  buildInputs = with pkgs; [
                    pkg-config
                    openssl
                    go_1_22
                    sqlite
                    llvmPackages.libclang.lib
                    rust-bin.stable.latest.minimal
                  ] ++ lib.optionals stdenv.isDarwin [
                    darwin.apple_sdk.frameworks.Security
                    darwin.apple_sdk.frameworks.CoreServices
                  ];
                  withHoogle = true;
                };
                modules = [{
                  enableLibraryProfiling = true;
                  enableProfiling = true;
                  packages.plonk-verify.components.setup.build-tools =
                    pkgs.lib.mkForce (with pkgs; [ rust-bin.stable.latest.minimal ]);
                  packages.plonk-verify.components.library.preBuild = ''
                    export OUT_DIR=$out
                    export LIBCLANG_PATH=${pkgs.llvmPackages.libclang.lib}/lib
                  '';
                }];
              };
          })
        ];
      in with pkgs; flake // rec {
        packages.default = flake.packages."test-lurk-hs:exe:example-lurk-hs";
      }
    );
}
