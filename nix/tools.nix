# The two commands a project gets: `gemlock-lock`, which writes a
# Gemfile.lock Nix can build from, and the `bundle` shim the dev shell puts
# ahead of Bundler's own. Both are nix/gemlock.rb, run by the project's
# Ruby, and differ only in the name they are called by.
{
  pkgs,
  ruby,
  wrappedRuby,
  lockPlatforms,
}:
let
  script =
    name:
    pkgs.writeTextFile {
      inherit name;
      executable = true;
      destination = "/bin/${name}";
      text = ''
        #!${ruby}/bin/ruby
        BUNDLE = ${builtins.toJSON "${wrappedRuby}/bin/bundle"}
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
