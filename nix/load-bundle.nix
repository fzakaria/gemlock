# gemlock.lib.loadBundle: from a directory holding a Gemfile and its
# Gemfile.lock to everything a project needs from Nix.
#
#   bundle = loadBundle { inherit pkgs; src = ./.; };
#
#   bundle.gems        one derivation per locked gem, as an overridable scope
#   bundle.env         the gems linked into one GEM_HOME, plus a wrapped ruby
#   bundle.shell { }   a dev shell where bundle exec and rails just work
#   bundle.app { }     a package exposing chosen gem executables
#   bundle.lock        `nix run .#lock`: relock with checksums and platforms
#   bundle.ruby        the Ruby everything above is built against
#   bundle.lockfile    the parsed Gemfile.lock
{ gemlockLib }:
{
  pkgs,
  # The project directory. Path-sourced gems resolve relative to it.
  src,
  gemfile ? src + "/Gemfile",
  lockfile ? src + "/Gemfile.lock",
  # Derived from .ruby-version, then the lock's RUBY VERSION, then pkgs.ruby.
  ruby ? null,
  # Bundler groups to build. null is every gem in the lock, which is what a
  # development shell wants; an app narrows this to [ "default" "production" ].
  groups ? null,
  # { <gem> = [ group ]; } to override what nix reads out of the Gemfile.
  gemGroups ? null,
  # An overlay on the gem scope: final: prev: { pg = prev.pg.overrideAttrs ...; }
  overrides ? (final: prev: { }),
  # { <gem> = src; } to replace a git or path gem's source with a fetch of
  # your own, for example a fetchFromGitHub with a hash.
  sources ? { },
  # Platforms `nix run .#lock` asks Bundler to lock for.
  lockPlatforms ? [
    "ruby"
    "x86_64-linux"
    "aarch64-linux"
    "arm64-darwin"
    "x86_64-darwin"
  ],
  # The name of the environment derivation.
  name ? "gemlock-${baseNameOf (toString src)}",
}@args:
let
  inherit (pkgs) lib;
  inherit (builtins) readFile pathExists;

  # A project that has not been locked yet still gets a shell, with a Ruby
  # and the lock tool in it and a note saying what to do next.
  hasLock = pathExists lockfile;
  emptyLock = {
    sources = [ ];
    specs = [ ];
    platforms = [ ];
    dependencies = [ ];
    checksums = { };
    rubyVersion = null;
    bundledWith = null;
  };
  parsedLock = if hasLock then gemlockLib.parseLockfile (readFile lockfile) else emptyLock;

  groupsByGem =
    if gemGroups != null then
      gemGroups
    else if pathExists gemfile then
      gemlockLib.parseGemfileGroups (readFile gemfile)
    else
      { };

  # Every group the Gemfile mentions, so an app can tell Bundler which ones
  # it was built without.
  allGroups = lib.unique (lib.concatLists (lib.attrValues groupsByGem) ++ [ "default" ]);

  ruby' = import ./ruby.nix {
    inherit pkgs src;
    lock = parsedLock;
    requested = ruby;
  };

  resolved = gemlockLib.resolve {
    lock = parsedLock;
    local = gemlockLib.platform.fromHostPlatform pkgs.stdenv.hostPlatform;
    inherit groups;
    gemGroups = groupsByGem;
  };

  gems = import ./gems.nix {
    inherit
      pkgs
      src
      resolved
      overrides
      sources
      ;
    ruby = ruby';
  };

  env = import ./env.nix {
    inherit pkgs name gems;
    ruby = ruby';
    lock = parsedLock;
  };

  tools = import ./tools.nix {
    inherit pkgs lockPlatforms;
    ruby = ruby';
    inherit (env) wrappedRuby;
  };

  bundle = {
    inherit gems env resolved;
    ruby = ruby';
    lockfile = parsedLock;
    inherit (env) wrappedRuby;
    lock = tools.lockApp;

    shell = import ./shell.nix {
      inherit
        pkgs
        env
        tools
        hasLock
        ;
    };

    # A narrower bundle for an application: the same project with a
    # production group set, then its executables wrapped.
    app =
      {
        groups ? [
          "default"
          "production"
        ],
        ...
      }@appArgs:
      let
        narrowed = import ./load-bundle.nix { inherit gemlockLib; } (args // { inherit groups; });
      in
      import ./app.nix {
        inherit pkgs gemfile lockfile;
        env = narrowed.env;
        ruby = ruby';
        without = lib.subtractLists groups allGroups;
      } (removeAttrs appArgs [ "groups" ]);
  };
in
bundle
