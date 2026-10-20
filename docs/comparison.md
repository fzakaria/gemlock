# Comparison

gemlock reads `Gemfile.lock` as is, matches platforms the way RubyGems
does, patches precompiled binaries for NixOS and never runs Ruby at
evaluation time. Each of the others misses at least one of those.

| tool                                                             | hashes from            | platform match                                     | precompiled binaries               | IFD             |
| ---------------------------------------------------------------- | ---------------------- | -------------------------------------------------- | ---------------------------------- | --------------- |
| [bundix](https://github.com/nix-community/bundix) + `bundlerEnv` | generated `gemset.nix` | none, `force_ruby_platform`                        | none                               | no              |
| [ruby-nix](https://github.com/inscapist/ruby-nix)                | its own `gemset.nix`   | own heuristic, ignores libc                        | `autoPatchelfHook`                 | no              |
| [gems4nix](https://github.com/omc/gems4nix)                      | `Gemfile.lock`         | table of four systems, string equality             | unpatched, ran only through nix-ld | yes, for groups |
| [packnix-bundler](https://github.com/tomberek/packnix-bundler)   | `Gemfile.lock`         | string equality with the host, picks wrong gem     | never ran                          | no              |
| gemlock                                                          | `Gemfile.lock`         | `Gem::Platform#===` port, checked against RubyGems | `autoPatchelfHook`                 | no              |

## Notes

- **bundix + bundlerEnv** downloads every gem a second time to hash it
  into `gemset.nix`, and the nixpkgs manual's answer to platform gems is
  to compile them all from source. Its wrappers pin `BUNDLE_GEMFILE` to a
  store copy and freeze, so in a dev shell a Gemfile edit does nothing
  until a rebuild. The pull request for platform gems, bundix#68, was open
  from 2019 to 2026 and closed unmerged.
- **ruby-nix** forks bundix and `bundlerEnv`, keeps the project Gemfile
  live, and handles platform gems with a matcher of its own: any cpu
  containing `arm`, `amd` or `aarch` counts as ARM, and libc is ignored,
  so `x86_64-linux-gnu` and `x86_64-linux-musl` are the same to it.
- **gems4nix** reads the lock and maps four Nix systems to lists of
  accepted platform strings, compared by equality. It accepts musl builds
  on a glibc host, throws on any other system, leaves precompiled
  binaries with `/lib64/ld-linux-x86-64.so.2` as their interpreter, and
  runs Ruby at evaluation time to read Gemfile groups.
- **packnix-bundler** compares the lock's platform strings with the
  host's. The host reports `x86_64-linux-gnu`, sorbet publishes
  `x86_64-linux`, nothing matched and it installed the aarch64 build.
- **gemlock** ports `Gem::Platform#initialize`, `#===` and Bundler's
  specificity score. A Ruby script asks RubyGems about 36 gem platforms
  against 11 hosts and the Nix port fails its test on any row that
  differs, which covers the gnu suffix, musl in both directions,
  `universal-darwin`, darwin versions and `arm-linux` on `armv7l`.
