# Design

The lockfile already has everything Nix needs. gemlock reads it.

## Where the hashes were all along

The old pipeline was `Gemfile` to `Gemfile.lock` by Bundler, then
`Gemfile.lock` to `gemset.nix` by bundix, which downloaded every gem to
hash it. The second step existed because the lock had no hashes.

Bundler 2.6 (December 2024) added `bundle lock --add-checksums`, which
writes a `CHECKSUMS` section:

```
CHECKSUMS
  nokogiri (1.19.4-x86_64-linux-gnu) sha256=379fae440b28915e3f19d752ce2dcf8465ed2b2fbefd2a7ca0dd497bc981a06a
  racc (1.8.1) sha256=4a7f6929691dbec8b5209a0b373bc2614882b55fc5d2e447a21aaa691303d62f
```

That hex is the sha256 of the `.gem` file, which is what `fetchurl` wants
after `builtins.convertHash`. A `GIT` section always records a full
commit, and `builtins.fetchGit` with a full commit is pure. A `PATH`
section points into the project. So every source in the lock is
fetchable with nothing but the lock.

gemlock is not the first to notice this; `omc/gems4nix` and
`tomberek/packnix-bundler` both read the lock directly. The design here
differs in where the work goes, below.

## The parser

`lib/lockfile.nix` is a fold over lines. The format is indentation:
column zero is a section, two spaces an option or list entry, four a
spec, six a spec's dependency. It reads `GEM`, `GIT`, `PATH`,
`PLATFORMS`, `DEPENDENCIES`, `CHECKSUMS`, `RUBY VERSION` and `BUNDLED
WITH`, refuses `PLUGIN SOURCE`, and errors on anything else at column
zero rather than guessing. Every `Gemfile.lock` in nixpkgs is a test
fixture; they predate `CHECKSUMS`, so the parser is exercised with and
without it.

## Choosing a platform

A lock resolved for several platforms lists a gem once per platform:

```
nokogiri (1.19.4-arm64-darwin)
nokogiri (1.19.4-x86_64-linux-gnu)
nokogiri (1.19.4-x86_64-linux-musl)
sorbet-static (0.6.13573-universal-darwin)
sorbet-static (0.6.13573-x86_64-linux)
```

Which one a host gets is not string equality. RubyGems parses
`x86_64-linux-gnu` into cpu, os and libc, and `Gem::Platform#===` says
that a gem for `x86_64-linux-gnu` runs on a Ruby reporting
`x86_64-linux`, that `universal-darwin` runs on any Darwin, and that
`x86_64-linux` runs on a musl host while `x86_64-linux-gnu` does not.
`lib/platform.nix` ports `Gem::Platform#initialize` and `#===` and
Bundler's specificity score, and `tests/platform.nix` holds a truth table
RubyGems 3.7 produced for the same inputs. Getting this wrong is the bug
that picks an aarch64 sorbet on x86_64.

With the variant chosen, the closure is walked over that variant's
dependencies. The source build of nokogiri depends on mini_portile2; the
precompiled one does not.

## What the gems are built with

Each gem is nixpkgs' `buildRubyGem`. It knows how to install a `.gem`,
how to lay a git checkout out under `bundler/gems/` the way Bundler
looks for it, and how to write binstubs. gemlock supplies the input and
two decisions:

- A precompiled gem on Linux goes through `autoPatchelfHook`. A binary
  such as `sorbet-static` ships with `/lib64/ld-linux-x86-64.so.2` as
  its interpreter, which does not exist on NixOS or in a build sandbox.
  On a host with nix-ld it appears to work, which hides the problem
  until it reaches CI.
- nixpkgs' `defaultGemConfig` is applied to source builds only, since
  its fixes assume compilation.

The gems form a `lib.makeScope`, so a gem is overridden like any other
package and an overlay replaces a per-gem configuration table.

## The shell and Bundler

Bundler at run time wants the `Gemfile`, its lock, the gems on
`GEM_PATH`, and a git gem under `bundler/gems/` in `GEM_HOME`. In a dev
shell, gemlock sets `GEM_HOME` and `GEM_PATH` and leaves Bundler to find
the project's own `Gemfile`, with nothing frozen, so `bundle lock` can
write. A packaged app pins `BUNDLE_GEMFILE` to a store copy, freezes, and
names the groups it was built without.

`BUNDLE_VERSION=system` is set everywhere. Without it Bundler 2.3 and
later reads `BUNDLED WITH`, notices a different version is running, and
tries to install the locked one into `GEM_HOME`, which is a store path.

The `bundle` shim exists because `bundle install` has no useful meaning
when Nix builds the gems, and the next best thing is to make it update
the lock and say so.

## What is pure

Everything evaluates without import-from-derivation. The Gemfile's
groups come from a small Nix reader of `group ... do` blocks and `group:`
keywords, not from running Ruby. Hashes come from the lock. The only
evaluation-time fetch is `builtins.fetchGit` for a git gem, which the
lock has no content hash for; `sources` replaces it.
