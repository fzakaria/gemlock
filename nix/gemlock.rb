# Shared body of `gemlock-lock` and the `bundle` shim; nix/tools.nix
# prepends BUNDLE (the real bundle) and PLATFORMS (what to lock for).
#
# As gemlock-lock:   gemlock-lock [bundle lock options]
#   bundle lock --add-checksums --add-platform <PLATFORMS> <options>
#
# As bundle: the subcommands that would install gems are turned into their
# lock-only forms, since the gems live in the store and Nix builds them.
# Everything else goes to Bundler unchanged.
#   bundle install          -> relock
#   bundle add GEM ...      -> bundle add GEM ... --skip-install, then relock
#   bundle remove GEM ...   -> bundle remove GEM ..., then relock
#   bundle update [GEM...]  -> relock with --update [GEM...]

# A read-only GEM_HOME is the point; stop Bundler from trying to install a
# different Bundler into it.
ENV["BUNDLE_VERSION"] = "system"

def relock(extra = [])
  system(BUNDLE, "lock", "--add-checksums", "--add-platform", *PLATFORMS, *extra) || exit($?.exitstatus)
  warn "gemlock: Gemfile.lock updated. Re-enter the shell (direnv reload, or exit and `nix develop`) to build the new gems."
end

if File.basename($0) == "gemlock-lock"
  relock(ARGV)
  exit
end

case ARGV[0]
when "install"
  warn "gemlock: gems are built by Nix, so `bundle install` only updates Gemfile.lock."
  relock
when "add"
  args = ARGV[1..]
  system(BUNDLE, "add", *args, "--skip-install") || exit($?.exitstatus)
  relock
when "remove"
  system(BUNDLE, "remove", *ARGV[1..]) || exit($?.exitstatus)
  relock
when "update"
  relock(["--update", *ARGV[1..]])
else
  exec(BUNDLE, *ARGV)
end
