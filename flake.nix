{
  description = "Romaji search for Japanese text in Vim and Neovim on goda.vim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    goda-nix = {
      url = "github:airRnot1106/goda.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, goda-nix, ... }:
    let
      version = "0.1.0";

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ] (system: f nixpkgs.legacyPackages.${system});

      build = pkgs: rec {
        # GPL, because it is made from the SKK dictionaries. It stays a data file
        # next to the binary, and is not part of this repository.
        dictionary = pkgs.fetchurl {
          url = "https://github.com/oguna/migemo-compact-dict-latest/releases/download/v0.2/migemo-compact-dict";
          hash = "sha256-+jrCQLM1iSIvzUCRDe0sFpc3TgGvFNwrtd32g6oumho=";
        };

        plugin = goda-nix.lib.buildGodaPlugin pkgs {
          inherit version;
          src = ./.;
          vendorHash = "sha256-vCGTOsjo38KFNjtvhKrc8pt9Q3pRi8+yqwNoJSMF0J8=";
          postInstall = ''
            install -Dm444 ${dictionary} $out/share/goda-ks/migemo-compact-dict
          '';
        };

        goTest =
          name: nativeBuildInputs: command:
          plugin.binary.overrideAttrs (prev: {
            name = "goda-ks-${name}";
            doCheck = true;
            nativeBuildInputs = prev.nativeBuildInputs ++ nativeBuildInputs;
            checkPhase = ''
              runHook preCheck
              export HOME=$TMPDIR
              export GODA_KS_TEST_DICT=${dictionary}
              ${command}
              runHook postCheck
            '';
            installPhase = "touch $out";
          });
      };
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          inherit (build pkgs) dictionary plugin;
        in
        {
          inherit dictionary;
          default = plugin;
          vim-plugin = plugin;
          goda-ks = plugin.binary;
          goda-vim = plugin.godaVim;
        }
      );

      checks = forAllSystems (
        pkgs:
        let
          inherit (build pkgs) goTest;
        in
        {
          unit = goTest "unit" [ ] "go test ./internal/... ./migemo/...";
          e2e = goTest "e2e" [
            pkgs.vim
            pkgs.neovim
          ] "GODA_KS_E2E_STRICT=1 go test -v -count=1 ./e2e";
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            (build pkgs).plugin.binary.go
            pkgs.vim
            pkgs.neovim
          ];
        };
      });
    };
}
