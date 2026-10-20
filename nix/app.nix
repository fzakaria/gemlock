# bundle.app { pname; exes; }: the executables of a bundle as a package.
#
# Each requested executable becomes bin/<exe>, a Ruby script that pins
# Bundler to a store copy of the Gemfile and lock, points RubyGems at the
# environment, loads bundler/setup and runs the gem's own executable. The
# gem that owns an executable is looked up from the installed gemspecs at
# build time, so a wrong name fails the build rather than the first run.
#
# `without` is the groups the environment was built without. Bundler is
# told so through BUNDLE_WITHOUT; otherwise bundler/setup would look for
# the development gems the lock lists and refuse to start.
{
  pkgs,
  ruby,
  env,
  gemfile,
  lockfile,
  without,
}:
{
  pname,
  exes,
  version ? env.gems.${pname}.version or "0",
  # Extra files Bundler needs next to the Gemfile at run time: a vendored
  # path gem, a .ruby-version the Gemfile reads.
  extraConfigPaths ? [ ],
  postBuild ? "",
  meta ? { },
  ...
}@args:
let
  inherit (pkgs) lib;

  confDir = pkgs.runCommand "${pname}-bundle-config" { } ''
    mkdir -p $out
    cp ${gemfile} $out/Gemfile
    cp ${lockfile} $out/Gemfile.lock
    ${lib.concatMapStringsSep "\n" (p: "cp -r ${p} $out/") extraConfigPaths}
  '';
in
pkgs.stdenvNoCC.mkDerivation (
  removeAttrs args [
    "exes"
    "extraConfigPaths"
    "postBuild"
  ]
  // {
    inherit pname version;
    dontUnpack = true;
    nativeBuildInputs = [ ruby ];

    buildPhase = ''
      runHook preBuild
      mkdir -p $out/bin
      ruby ${./binstubs.rb} \
        "${ruby}/bin/ruby" \
        "${env.gemHome}" \
        "${confDir}/Gemfile" \
        "${lib.concatStringsSep ":" without}" \
        "$out/bin" \
        ${lib.escapeShellArgs exes}
      ${postBuild}
      runHook postBuild
    '';

    passthru = (args.passthru or { }) // {
      inherit env confDir;
    };

    meta = {
      mainProgram = builtins.head exes;
      platforms = ruby.meta.platforms;
    }
    // meta;
  }
)
