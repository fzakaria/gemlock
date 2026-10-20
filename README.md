<p align="center">
  <img src="docs/img/gemlock.svg" width="96" height="96" alt="" />
</p>

<h1 align="center">gemlock</h1>

<p align="center">
  <b>Ruby gems for Nix, straight from <code>Gemfile.lock</code>.</b><br />
  Bundler already writes every checksum Nix needs. gemlock reads them and
  builds the gems, a dev shell and your app, with nothing to generate and
  no import-from-derivation.
</p>

<p align="center">
  <a href="docs/using.md">Using</a> ·
  <a href="docs/design.md">Design</a>
</p>

<p align="center">
  <a href="https://github.com/fzakaria/gemlock/actions/workflows/check.yml"><img src="https://github.com/fzakaria/gemlock/actions/workflows/check.yml/badge.svg?branch=main" alt="check" /></a>
</p>

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.gemlock.url = "github:fzakaria/gemlock";
  inputs.gemlock.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, gemlock, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      bundle = gemlock.lib.loadBundle { inherit pkgs; src = ./.; };
    in {
      devShells.x86_64-linux.default = bundle.shell { };
      packages.x86_64-linux.default = bundle.app { pname = "myapp"; exes = [ "myapp" ]; };
      apps.x86_64-linux.lock = bundle.lock;
    };
}
```

## Quickstart

```console
$ nix flake init -t github:fzakaria/gemlock
# writes Gemfile.lock with checksums, for every platform
$ nix run .#lock
# ruby, bundle and every locked gem
$ nix develop
$ bundle exec rake
```

Inside the shell, `bundle add`, `bundle install` and `bundle update` only
update the lock. Re-enter the shell and the new gems are built.

## What you get

| attribute              | what it is                                                  |
| ---------------------- | ----------------------------------------------------------- |
| `bundle.gems.<name>`   | one derivation per gem; `overrideAttrs` works on it         |
| `bundle.env`           | the gems in one `GEM_HOME`, with a setup hook               |
| `bundle.shell { }`     | a dev shell: ruby, the gems, and a `bundle` that only locks |
| `bundle.app { exes; }` | a package with the named gem executables in `bin/`          |
| `bundle.lock`          | `nix run .#lock`: relock with checksums and platforms       |
| `bundle.ruby`          | the Ruby in use, picked from `.ruby-version` or the lock    |

## Prior art

What each tool does with the same lock: precompiled `nokogiri`, the
`sorbet-static` binary and `rack` from git, on x86_64-linux.

| tool                                                             | hashes from            | platform gems                                     | ELF binaries on NixOS   | Ruby at eval time |
| ---------------------------------------------------------------- | ---------------------- | ------------------------------------------------- | ----------------------- | ----------------- |
| [bundix](https://github.com/nix-community/bundix) + `bundlerEnv` | generated `gemset.nix` | source builds only (`force_ruby_platform`)        | n/a                     | no                |
| [ruby-nix](https://github.com/inscapist/ruby-nix)                | its own `gemset.nix`   | yes                                               | not checked             | no                |
| [gems4nix](https://github.com/omc/gems4nix)                      | `Gemfile.lock`         | yes                                               | unpatched, needs nix-ld | yes, for groups   |
| [packnix-bundler](https://github.com/tomberek/packnix-bundler)   | `Gemfile.lock`         | wrong variant (string match picks aarch64 on x86) | not checked             | no                |
| gemlock                                                          | `Gemfile.lock`         | yes, by RubyGems' rules, tested against RubyGems  | `autoPatchelfHook`      | no                |

## Caveats

- The lock has to come from Bundler 2.6 or newer with `--add-checksums`,
  which is what `nix run .#lock` does.
- Git gems are fetched at evaluation time. The lock records a commit but
  no content hash, so pass `sources` to pin one with a hash.
- A native extension built from source still needs its libraries. nixpkgs'
  `defaultGemConfig` covers the common ones; anything else is an
  `overrides` entry.
- Gemfile groups are read from `group` blocks and `group:` keywords, not
  from `gemspec`, `eval_gemfile` or conditionals. Pass `gemGroups` to be
  exact.
- Bundler plugins, JRuby and Windows are out of scope.

## License

MIT, see [LICENSE](LICENSE).
