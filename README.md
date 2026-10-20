# gemlock

Ruby gems for Nix, from `Gemfile.lock` alone. No bundix, no gemset.nix, no
import-from-derivation.

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

**Documentation:** [How to use it](./docs/using.md) ·
[Design](./docs/design.md) · [Caveats](./docs/caveats.md)

## Status

![check workflow](https://github.com/fzakaria/gemlock/actions/workflows/check.yml/badge.svg?branch=main)

Works on the two examples in this repository, checked on every push on
Linux and macOS: a small project with a precompiled `nokogiri`, the
`sorbet-static` binary and a git-sourced `rack`, and a Rails 8 lock with
121 gems. Not yet used in anger beyond that.

## Why

Bundler 2.6 writes a `CHECKSUMS` section into `Gemfile.lock`: a sha256 for
every gem. A `GIT` section always carries the full commit. That is every
hash Nix needs, so the lockfile can be read directly and the bundix step,
with its separately generated and separately stale `gemset.nix`, goes away.

Reading the lock directly also ends the long-standing trouble with
platform-specific gems. The lock lists every variant Bundler resolved
(`nokogiri (1.19.4-arm64-darwin)`, `nokogiri (1.19.4-x86_64-linux-gnu)`,
...) each with its own checksum, and gemlock picks the one for the host by
the same rules RubyGems and Bundler use. Precompiled gems are preferred
over source builds, and on Linux their binaries are patched to run from
the store.

## Quickstart

```console
$ nix flake init -t github:fzakaria/gemlock
$ nix run .#lock          # writes Gemfile.lock with checksums, for every platform
$ nix develop             # ruby, bundle and every locked gem
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

## License

MIT, see [LICENSE](LICENSE).
