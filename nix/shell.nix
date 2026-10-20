# bundle.shell { packages = [ ... ]; }: a development shell.
#
# The gems are on GEM_PATH and the wrapped Ruby is on PATH, so `ruby`,
# `irb`, `bundle exec`, `rails server` and `require "bundler/setup"` all
# find the locked gems. Bundler reads the Gemfile from the working
# directory as usual; nothing is frozen, so `bundle lock` works too. The
# `bundle` on PATH is a shim: subcommands that would install into the
# store are turned into lock-only ones, and the rest pass straight through.
{
  pkgs,
  env,
  tools,
  hasLock,
}:
{
  packages ? [ ],
  shellHook ? "",
  ...
}@args:
pkgs.mkShell (
  removeAttrs args [
    "packages"
    "shellHook"
  ]
  // {
    packages = [
      tools.bundleShim
      tools.lockTool
      env.wrappedRuby
      env
    ]
    ++ packages;

    # The setup hook on `env` has already exported GEM_HOME and GEM_PATH by
    # the time this runs. BUNDLE_GEMFILE is unset on purpose: Bundler finds
    # the project's own Gemfile, and `bundle lock` can write next to it.
    shellHook = ''
      unset BUNDLE_GEMFILE BUNDLE_FROZEN BUNDLE_PATH
      ${pkgs.lib.optionalString (!hasLock) ''
        echo "gemlock: no Gemfile.lock yet. Run \`gemlock-lock\` (or \`bundle install\`) to create one, then re-enter the shell." >&2
      ''}
      ${shellHook}
    '';
  }
)
