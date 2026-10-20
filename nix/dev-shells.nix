# The shells behind `nix develop` in this repository.
{ pkgs, examples }:
{
  # Working on gemlock itself: the formatter, a Ruby for regenerating the
  # platform truth table, and the two example bundles' lock tools.
  default = pkgs.mkShellNoCC {
    packages = [
      (import ./formatter.nix { inherit pkgs; }).wrapper
      pkgs.ruby
    ];
  };

  # What a consumer gets: `nix develop .#basic` is examples/basic's shell.
  basic = examples.basic.shell { };
  rails = examples.rails.shell { };
}
