# The gems linked into one GEM_HOME, and a Ruby whose every executable
# already points at it.
#
# `env` is the gem forest: lib/ruby/gems/<abi>/{gems,specifications,...}
# across every gem, plus their binstubs under bin/. Its setup hook exports
# GEM_HOME and GEM_PATH, so putting it in a derivation's buildInputs is
# enough. `wrappedRuby` is ruby, irb, bundle and friends with the same two
# variables baked in, for use from a PATH.
{
  pkgs,
  name,
  ruby,
  gems,
  lock,
}:
let
  inherit (pkgs) lib;
  gemDerivations = lib.attrValues (lib.filterAttrs (_: lib.isDerivation) gems);

  gemHomeOf = env: "${env}/${ruby.gemPath}";

  env = pkgs.buildEnv {
    inherit name;
    paths = gemDerivations;
    pathsToLink = [
      "/lib"
      "/bin"
      "/share"
    ];
    # BUNDLE_VERSION=system: Bundler 2.3+ otherwise tries to install the
    # lock's BUNDLED WITH version next to itself, into a store path.
    postBuild = ''
      mkdir -p $out/nix-support
      cat > $out/nix-support/setup-hook <<EOF
      export GEM_HOME="${gemHomeOf (placeholder "out")}"
      export GEM_PATH="${gemHomeOf (placeholder "out")}"
      export BUNDLE_VERSION=system
      EOF
    '';
    passthru = {
      inherit ruby gems wrappedRuby;
      gemHome = gemHomeOf env;
      bundledWith = lock.bundledWith;
    };
    meta.platforms = ruby.meta.platforms;
  };

  wrappedRuby = pkgs.stdenvNoCC.mkDerivation {
    name = "${name}-ruby-${ruby.version}";
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      for exe in ${ruby}/bin/*; do
        makeWrapper "$exe" "$out/bin/$(basename "$exe")" \
          --set GEM_HOME "${gemHomeOf env}" \
          --set GEM_PATH "${gemHomeOf env}" \
          --set BUNDLE_VERSION system
      done
    '';
    passthru = {
      inherit ruby env;
      inherit (ruby) version gemPath;
    };
    meta = ruby.meta;
  };
in
env
