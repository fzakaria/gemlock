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

RUBY_PLATFORM_NAME = "ruby"
UNIX_OSES = %w[linux darwin].freeze

def bundle_lock(*args)
  system(BUNDLE, "lock", *args) || exit($?.exitstatus)
end

# Does one locked variant of a gem run on the platform? The same test the
# Nix side makes, through RubyGems itself.
def runs_on?(spec, platform)
  return true if spec.platform.to_s == RUBY_PLATFORM_NAME

  Gem::Platform.new(spec.platform) === platform
end

# Gems that publish Unix builds, so a missing build for a listed Unix
# platform is a gap and not a Windows- or JRuby-only gem.
def publishes_unix_builds?(specs)
  specs.any? { |s| s.platform.to_s != RUBY_PLATFORM_NAME && UNIX_OSES.include?(Gem::Platform.new(s.platform).os) }
end

# { "arm64-darwin" => ["sqlite3", ...] }: platforms the lock lists without
# the variants some gems need there. docs/using.md, "Lock", explains how
# Bundler produces such a lock.
def incomplete_platforms
  require "bundler"
  lock = Bundler::LockfileParser.new(Bundler.read_file(Bundler.default_lockfile))
  by_name = lock.specs.group_by(&:name)

  PLATFORMS.each_with_object({}) do |name, gaps|
    next if name == RUBY_PLATFORM_NAME

    platform = Gem::Platform.new(name)
    missing = by_name.select do |_, specs|
      publishes_unix_builds?(specs) && specs.none? { |s| runs_on?(s, platform) }
    end
    gaps[name] = missing.keys unless missing.empty?
  end
end

def relock(extra = [])
  bundle_lock("--add-checksums", "--add-platform", *PLATFORMS, *extra)

  # A platform that came back without its variants is removed and added
  # again on its own. Bundler then resolves it through its resolver, which
  # falls back to a gem's generic build when the precompiled one rejects
  # this Ruby, instead of the all-or-nothing platform completion that
  # produced the gap.
  gaps = incomplete_platforms
  gaps.each do |platform, gems|
    warn "gemlock: Gemfile.lock lists #{platform} but has no #{platform} build of #{gems.join(", ")}; re-adding the platform."
    system(BUNDLE, "lock", "--remove-platform", platform)
    bundle_lock("--add-platform", platform)
  end

  gaps = incomplete_platforms unless gaps.empty?
  gaps.each do |platform, gems|
    warn "gemlock: still no #{platform} build of #{gems.join(", ")}; see docs/using.md, \"Lock\"."
  end

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
