# Design

The lockfile already has everything Nix needs. gemlock reads it.

## The hashes

Bundler 2.6 (December 2024) added `bundle lock --add-checksums`, which
writes a `CHECKSUMS` section:

```
CHECKSUMS
  nokogiri (1.19.4-x86_64-linux-gnu) sha256=379fae440b28915e3f19d752ce2dcf8465ed2b2fbefd2a7ca0dd497bc981a06a
  racc (1.8.1) sha256=4a7f6929691dbec8b5209a0b373bc2614882b55fc5d2e447a21aaa691303d62f
```

That is the sha256 of the `.gem` file, which `fetchurl` takes after
`builtins.convertHash`. A `GIT` section records a full commit, which
`builtins.fetchGit` fetches purely. A `PATH` section points into the
project. bundix and `gemset.nix` existed to supply hashes the lock now
carries.

## The parser

`lib/lockfile.nix` folds over lines. Indentation is the grammar: column
zero a section, two spaces an option or list entry, four a spec, six a
dependency. An unknown section is an error. Every `Gemfile.lock` in
nixpkgs is a test fixture.

## Choosing a platform

A lock resolved for several platforms lists a gem once per platform:

```
nokogiri (1.19.4-arm64-darwin)
nokogiri (1.19.4-x86_64-linux-gnu)
nokogiri (1.19.4-x86_64-linux-musl)
sorbet-static (0.6.13573-universal-darwin)
```

The match is not string equality. RubyGems parses a platform into cpu,
os and version; `x86_64-linux-gnu` runs on a Ruby reporting
`x86_64-linux`, `universal-darwin` runs on any Darwin, `x86_64-linux`
runs on musl and `x86_64-linux-gnu` does not. `lib/platform.nix` ports
`Gem::Platform#initialize`, `#===` and Bundler's specificity score, and
`tests/platform.nix` checks the port against a truth table RubyGems 3.7
produced. The dependency closure follows the chosen variant, since the
source build of nokogiri needs mini_portile2 and the precompiled one does
not.

## Building gems

Each gem is nixpkgs' `buildRubyGem`. A precompiled gem on Linux goes
through `autoPatchelfHook`, since its binaries name
`/lib64/ld-linux-x86-64.so.2`. `defaultGemConfig` applies to source
builds only. The gems form a `lib.makeScope`, so overriding one is an
overlay.

## Bundler at run time

The shell sets `GEM_HOME` and `GEM_PATH` and leaves Bundler to find the
project's own `Gemfile`, unfrozen, so `bundle lock` can write. An app
pins `BUNDLE_GEMFILE` to a store copy and freezes. An env built for some
of the groups exports `BUNDLE_WITHOUT` for the rest, from its setup hook
and its wrapped Ruby: the lock still lists those gems, and `bundler/setup`
treats a locked gem it cannot find as an error unless its group is named
there. `BUNDLE_VERSION=system` is set everywhere; without it Bundler
tries to install the `BUNDLED WITH` version into the store. The `bundle`
shim turns `install`, `add`, `remove` and `update` into relocks.

## Purity

No import-from-derivation. Groups come from a Nix reader of `group`
blocks and `group:` keywords. The one evaluation-time fetch is
`builtins.fetchGit` for a git gem, which `sources` replaces.
