# Comparison

gemlock is the only one of these that reads `Gemfile.lock` directly, picks
platform variants by RubyGems' own rules, patches precompiled binaries for
NixOS and evaluates without import-from-derivation. The others each miss
at least one of those, and every gap below was hit with the same lock: a
precompiled `nokogiri`, the `sorbet-static` binary and `rack` from git, on
x86_64-linux.

| tool                                                             | hashes from            | platform gems                              | precompiled binaries               | IFD             |
| ---------------------------------------------------------------- | ---------------------- | ------------------------------------------ | ---------------------------------- | --------------- |
| [bundix](https://github.com/nix-community/bundix) + `bundlerEnv` | generated `gemset.nix` | source builds only (`force_ruby_platform`) | none                               | no              |
| [ruby-nix](https://github.com/inscapist/ruby-nix)                | its own `gemset.nix`   | yes                                        | `autoPatchelfHook`                 | no              |
| [gems4nix](https://github.com/omc/gems4nix)                      | `Gemfile.lock`         | yes                                        | unpatched, ran only through nix-ld | yes, for groups |
| [packnix-bundler](https://github.com/tomberek/packnix-bundler)   | `Gemfile.lock`         | wrong variant                              | never ran                          | no              |
| gemlock                                                          | `Gemfile.lock`         | yes, tested against RubyGems               | `autoPatchelfHook`                 | no              |

## Notes

- **bundix + bundlerEnv** is the nixpkgs default. It downloads every gem a
  second time to hash it into `gemset.nix`, and the nixpkgs manual's
  answer to platform gems is to compile everything from source. The pull
  request to fix that, bundix#68, was open from 2019 to 2026 and closed
  unmerged.
- **ruby-nix** forks bundix and `bundlerEnv` and handles platform gems,
  at the cost of its own gemset format and its own bundix.
- **gems4nix** reads the lock and picks variants correctly, but leaves
  precompiled binaries with `/lib64/ld-linux-x86-64.so.2` as their
  interpreter, so they only run on a host with nix-ld, and it runs Ruby at
  evaluation time to read Gemfile groups.
- **packnix-bundler** matches platform strings by equality. The host
  reports `x86_64-linux-gnu`, sorbet publishes `x86_64-linux`, nothing
  matched and it installed the aarch64 build.
- **gemlock** ports `Gem::Platform#===` and Bundler's specificity score,
  checks the port against a truth table RubyGems generates, builds with
  nixpkgs' `buildRubyGem`, and reads groups with a Nix parser.
