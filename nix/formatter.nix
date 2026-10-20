# `nix fmt` and the formatting check: treefmt over nixfmt for Nix and
# prettier at 80 columns for Markdown and YAML, configured here rather
# than through treefmt-nix so the flake keeps nixpkgs as its only input.
{ pkgs }:
let
  config = (pkgs.formats.toml { }).generate "treefmt.toml" {
    formatter.nixfmt = {
      command = "${pkgs.nixfmt}/bin/nixfmt";
      includes = [ "*.nix" ];
    };
    formatter.prettier = {
      command = "${pkgs.prettier}/bin/prettier";
      options = [
        "--write"
        "--print-width"
        "80"
      ];
      includes = [
        "*.md"
        "*.yml"
      ];
    };
  };

  wrapper = pkgs.writeShellScriptBin "treefmt" ''
    exec ${pkgs.treefmt}/bin/treefmt --config-file ${config} --tree-root-file flake.nix "$@"
  '';
in
{
  inherit config wrapper;

  # Fails when any tracked file would change.
  check =
    src:
    pkgs.runCommand "treefmt-check" { nativeBuildInputs = [ wrapper ]; } ''
      cp -r ${src} source
      chmod -R u+w source
      cd source
      treefmt --ci --no-cache
      touch $out
    '';
}
