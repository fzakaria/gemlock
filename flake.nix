{
  description = "gemlock: Ruby gems for Nix from Gemfile.lock alone";

  # nixpkgs is the only input. The formatter and the test tooling come out
  # of it too, so adding gemlock to a project adds one node to its lock.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Wiring only. The pure half (parsing, platforms, resolution) is lib/; the
  # half that builds derivations is nix/.
  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        builtins.listToAttrs (
          map (system: {
            name = system;
            value = f system;
          }) systems
        );
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      pureLib = import ./lib;
      loadBundle = import ./nix/load-bundle.nix { gemlockLib = pureLib; };

      # The two example projects, built the way a consumer would build them.
      examplesFor = pkgs: {
        basic = loadBundle {
          inherit pkgs;
          src = ./examples/basic;
        };
        rails = loadBundle {
          inherit pkgs;
          src = ./examples/rails;
        };
      };
    in
    {
      # gemlock.lib.loadBundle { pkgs; src = ./.; } is the whole API; the
      # rest is what it is built from, exposed for tests and for anyone who
      # wants only the lockfile parser.
      lib = pureLib // {
        inherit loadBundle;
      };

      templates.default = {
        path = ./templates/default;
        description = "A Ruby project built from its Gemfile.lock";
      };

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          examples = examplesFor pkgs;
        in
        {
          basic-env = examples.basic.env;
          rails-env = examples.rails.env;
          # `nix run .#rake -- --version`: a gem executable from a bundle.
          rake = examples.basic.app {
            pname = "rake";
            exes = [ "rake" ];
          };
        }
      );

      checks = forAllSystems (
        system:
        import ./nix/checks.nix {
          inherit self system nixpkgs;
          pkgs = pkgsFor system;
          examples = examplesFor (pkgsFor system);
        }
      );

      formatter = forAllSystems (system: (import ./nix/formatter.nix { pkgs = pkgsFor system; }).wrapper);

      devShells = forAllSystems (
        system:
        import ./nix/dev-shells.nix {
          pkgs = pkgsFor system;
          examples = examplesFor (pkgsFor system);
        }
      );
    };
}
