# How to use it

## Add the input

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.gemlock.url = "github:fzakaria/gemlock";
  inputs.gemlock.inputs.nixpkgs.follows = "nixpkgs";
}
```

gemlock has one input, nixpkgs, so this adds one node to your lock.

## Lock

gemlock reads hashes from the `CHECKSUMS` section of `Gemfile.lock`, which
Bundler 2.6 and later write on request. It also needs the lock to list the
platforms you build for, so that the precompiled variant of a gem is there
to pick. One command does both:

```console
$ nix run .#lock
```

It runs the Bundler of the Ruby your bundle uses, as:

```console
$ bundle lock --add-checksums --add-platform ruby x86_64-linux aarch64-linux arm64-darwin x86_64-darwin
```

Arguments pass through, so `nix run .#lock -- --update nokogiri` updates one
gem. The platform list is the `lockPlatforms` argument of `loadBundle`.

## Load the bundle

```nix
bundle = gemlock.lib.loadBundle {
  inherit pkgs;
  src = ./.;                   # the directory holding Gemfile and Gemfile.lock
};
```

`src` is only a base path. gemlock reads `Gemfile`, `Gemfile.lock` and
`.ruby-version` from it at evaluation time and copies nothing else into
the store, so editing an unrelated file in the project does not rebuild a
gem or an app. The two things that do depend on files under `src` are a
`PATH` gem, which copies only its own directory, and `extraConfigPaths`
on `bundle.app`. If you would rather be explicit, any path works,
including a `lib.fileset.toSource` holding just the two Bundler files.

Everything else is optional:

| argument        | default                                               | meaning                                                           |
| --------------- | ----------------------------------------------------- | ----------------------------------------------------------------- |
| `gemfile`       | `src + "/Gemfile"`                                    |                                                                   |
| `lockfile`      | `src + "/Gemfile.lock"`                               |                                                                   |
| `ruby`          | from `.ruby-version`, then the lock, then `pkgs.ruby` | the interpreter every gem is built against                        |
| `groups`        | `null`, meaning every gem                             | Bundler groups to include                                         |
| `gemGroups`     | read from the Gemfile                                 | `{ rspec = [ "test" ]; }` when the Gemfile is too dynamic to read |
| `overrides`     | `final: prev: { }`                                    | an overlay on the gem scope                                       |
| `sources`       | `{ }`                                                 | `{ <gem> = src; }` replacing a git or path gem's source           |
| `lockPlatforms` | the four nixpkgs systems and `ruby`                   | what `nix run .#lock` asks Bundler for                            |
| `name`          | `gemlock-<directory name>`                            | the environment's name                                            |

## The shell

```nix
devShells.default = bundle.shell {
  packages = [ pkgs.sqlite pkgs.nodejs ];   # anything else the project needs
};
```

Inside: `ruby`, `irb`, `bundle` and the executables of every locked gem are
on `PATH`; `GEM_HOME` and `GEM_PATH` point at the bundle. Bundler finds the
project's own `Gemfile` as usual and nothing is frozen, so `bundle exec`,
`rails server` and `require "bundler/setup"` work from the project
directory.

The gems live in the store, so Bundler cannot install into them. The
`bundle` on `PATH` is a shim that turns the subcommands which would try
into lock-only ones:

| you type              | what runs                                    |
| --------------------- | -------------------------------------------- |
| `bundle install`      | relock                                       |
| `bundle add GEM`      | `bundle add GEM --skip-install`, then relock |
| `bundle remove GEM`   | `bundle remove GEM`, then relock             |
| `bundle update [GEM]` | relock with `--update [GEM]`                 |
| anything else         | Bundler, unchanged                           |

After a relock, re-enter the shell. With direnv, `watch_file Gemfile.lock`
in `.envrc` does that for you; the template ships one.

## The gems

`bundle.gems` is a scope: `bundle.gems.nokogiri` is a derivation, and
`overrideAttrs` works on it. To change how a gem is built, pass an overlay:

```nix
bundle = gemlock.lib.loadBundle {
  inherit pkgs;
  src = ./.;
  overrides = final: prev: {
    pg = prev.pg.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.libpq ];
      buildFlags = [ "--with-pg-config=${pkgs.libpq.pg_config}/bin/pg_config" ];
    });
  };
};
```

nixpkgs' own per-gem fixes (`defaultGemConfig`) are applied first to every
gem built from source, so most native extensions need nothing.

A precompiled gem on Linux is run through `autoPatchelfHook` with
`libstdc++` and `zlib` available. One that links something else gets it
the same way:

```nix
overrides = final: prev: {
  grpc = prev.grpc.overrideAttrs (old: { buildInputs = old.buildInputs ++ [ pkgs.openssl ]; });
};
```

## Packaging an application

```nix
packages.default = bundle.app {
  pname = "mytool";
  exes = [ "mytool" ];
  groups = [ "default" "production" ];   # the default
};
```

Each name in `exes` becomes `bin/<name>`: a script that pins Bundler to a
store copy of the `Gemfile` and lock, frozen, and runs that gem's
executable the way `bundle exec` would. The gem owning an executable is
found at build time, so a misspelt name fails the build.

`groups` narrows the bundle; `development` and `test` gems are not built,
and the scripts tell Bundler so through `BUNDLE_WITHOUT`. `postBuild` runs
after the scripts are written, for wrapping them with `makeWrapper` when
the tool needs other programs on `PATH`.

## Ruby version

In order: the `ruby` you pass, `.ruby-version` in `src`, the `RUBY
VERSION` section of the lock, `pkgs.ruby`. A version is mapped to nixpkgs'
`ruby_<major>_<minor>`; for one nixpkgs does not ship, pass a derivation,
for example from
[nixpkgs-ruby](https://github.com/bobvanderlinden/nixpkgs-ruby). A lock
resolved under a different major.minor than the Ruby in use is an error,
because gems install under a per-version directory and extensions build
against that ABI.

## Git and path gems

A `GIT` section is fetched with `builtins.fetchGit` at the locked commit,
which is pure but happens at evaluation time, on every machine, with
network. `sources` replaces that with a fetch of your choosing:

```nix
sources.errgonomic = pkgs.fetchFromGitHub {
  owner = "omc"; repo = "errgonomic";
  rev = "f06314af89209f855019219fd198513855be0fd5";
  hash = "sha256-...";
};
```

A `PATH` section is built from `src + "/<remote>"`. Bundler reads a path
gem's gemspec from the project directory at run time, so in a dev shell
nothing more is needed; `bundle.app` takes `extraConfigPaths` for files
that have to sit next to the store copy of the Gemfile.
