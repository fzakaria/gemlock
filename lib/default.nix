# The pure half of gemlock: reading the lockfile and the Gemfile, matching
# platforms, and deciding which spec of each gem to build. Builtins only,
# so all of it works from a plain `nix eval` with no nixpkgs in sight.
{
  parseLockfile = import ./lockfile.nix;
  parseGemfileGroups = import ./gemfile.nix;
  platform = import ./platform.nix;
  resolve = import ./resolve.nix;
}
