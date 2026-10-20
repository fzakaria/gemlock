{
  description = "A Ruby project built from its Gemfile.lock";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    gemlock.url = "github:fzakaria/gemlock.nix";
    gemlock.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, gemlock, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      bundleFor =
        pkgs:
        gemlock.lib.loadBundle {
          inherit pkgs;
          src = ./.;
        };
    in
    {
      # `nix develop`: ruby, bundle and every locked gem.
      devShells = forAllSystems (pkgs: {
        default = (bundleFor pkgs).shell { };
      });

      # `nix run .#lock`: write a Gemfile.lock with checksums for every
      # platform gemlock builds for. Run it after editing the Gemfile.
      apps = forAllSystems (pkgs: {
        lock = (bundleFor pkgs).lock;
      });
    };
}
