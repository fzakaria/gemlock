# Caveats

- **Bundler 2.6 or newer** has to have written the lock, with
  `--add-checksums`. The nixpkgs Ruby 3.4 bundles 2.6.9. A lock without a
  `CHECKSUMS` section is an error naming the gem and the command to run.
- **Git gems are fetched at evaluation time.** The lock records a commit
  but no content hash, so there is no substitutable derivation. Every
  machine evaluating the flake fetches the repository. Pass `sources` for
  a gem you want cached.
- **Source-built native extensions still need their libraries.** Precompiled
  variants avoid this for nokogiri, sqlite3 and the other big ones, and
  nixpkgs' `defaultGemConfig` covers over a hundred more. Anything else
  needs an `overrides` entry.
- **Group reading is a subset of the Gemfile.** `group ... do` blocks and
  `group:` keywords are read; `gemspec`, `eval_gemfile`, conditionals and
  `Dir.glob` are not, and a gem they declare lands in `default`. This only
  changes what `bundle.app` leaves out. Pass `gemGroups` to be exact.
- **A gem with no variant for your platform is an error**, as it would be
  for Bundler. Run `nix run .#lock` so the lock covers the platform.
- **Bundler plugins, JRuby and Windows platforms** are out of scope.
- **nixpkgs ships Ruby 3.3, 3.4 and 4.0.** Another version has to be passed
  in as `ruby`.
- **macOS** is checked in CI on an Apple Silicon runner; the author's
  machine is Linux.
