# The two commands a project gets: `gemlock-lock`, which writes a
# Gemfile.lock Nix can build from, and the `bundle` shim the dev shell puts
# ahead of Bundler's own. Both are nix/gemlock.rb, run by the project's
# Ruby, and differ only in the name they are called by.
#
# Neither depends on the gem environment. The lock tool has to run on a
# lock that has no checksums yet, which is exactly the lock the gems cannot
# be evaluated from; in the dev shell the environment's GEM_PATH is already
# exported, so the shim's pass-through finds the gems anyway.
{
  pkgs,
  ruby,
  lockPlatforms,
}:
let
  inherit (pkgs) lib;

  # `bundle lock --add-checksums` arrived in Bundler 2.6, which first shipped
  # with Ruby 3.4. An older Ruby locks with nixpkgs' Bundler built against it
  # and keeps its own Bundler for everything else.
  bundledBundlerTooOld = lib.versionOlder (toString ruby.version) "3.4";
  lockBundle =
    if bundledBundlerTooOld then
      "${pkgs.bundler.override { inherit ruby; }}/bin/bundle"
    else
      "${ruby}/bin/bundle";

  script =
    name:
    pkgs.writeTextFile {
      inherit name;
      executable = true;
      destination = "/bin/${name}";
      text = ''
        #!${ruby}/bin/ruby
        BUNDLE = ${builtins.toJSON "${ruby}/bin/bundle"}
        LOCK_BUNDLE = ${builtins.toJSON lockBundle}
        PLATFORMS = ${builtins.toJSON lockPlatforms}
        ${builtins.readFile ./gemlock.rb}
      '';
    };

  lockTool = script "gemlock-lock";
  bundleShim = script "bundle";
in
{
  inherit lockTool bundleShim;

  # `nix run .#lock`.
  lockApp = {
    type = "app";
    program = "${lockTool}/bin/gemlock-lock";
    meta.description = "Write a Gemfile.lock with checksums for every platform gemlock builds for";
  };
}
