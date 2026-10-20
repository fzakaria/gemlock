# `nix flake check` runs these.
#
# The eval tests return a summary only after their assertions hold, so
# serialising it into a derivation makes evaluation the test and the build
# step just writes it out. The build tests then prove the environments run
# inside the sandbox, with no nix-ld to paper over an unpatched binary.
{
  self,
  system,
  nixpkgs,
  pkgs,
  examples,
}:
let
  evalTest =
    name:
    pkgs.runCommand "test-${name}" {
      summary = builtins.toJSON (
        import (../tests + "/${name}.nix") {
          gemlock = self;
          inherit nixpkgs;
        }
      );
    } ''echo "$summary" > $out'';

  basic = examples.basic;
  rails = examples.rails;
in
{
  lockfile = evalTest "lockfile";
  platform = evalTest "platform";
  gemfile = evalTest "gemfile";
  resolve = evalTest "resolve";

  # The small example, end to end: a precompiled extension loads, a
  # precompiled binary runs, a git gem is where Bundler looks for it, and
  # the whole thing works both bare and through bundler/setup.
  basic-env =
    pkgs.runCommand "test-basic-env"
      {
        nativeBuildInputs = [
          basic.env
          basic.wrappedRuby
        ];
      }
      ''
        cp -r ${../examples/basic} project
        chmod -R u+w project
        cd project

        ruby -e 'require "nokogiri"; puts Nokogiri::HTML("<h1>ok</h1>").at("h1").text' | grep -x ok
        ruby -e 'require "bundler/setup"; require "rack"; require "nokogiri"; puts Rack::RELEASE' | grep -x 3.1.8
        bundle exec rake --version | grep 13.4.2
        "$GEM_HOME"/gems/sorbet-static-*/libexec/sorbet --version | grep 0.6.13573
        touch $out
      '';

  # A gem executable packaged on its own.
  rake-app = pkgs.runCommand "test-rake-app" { } ''
    ${self.packages.${system}.rake}/bin/rake --version | grep 13.4.2
    touch $out
  '';

  # Rails 8: 121 gems, precompiled sqlite3 and nokogiri, source-built
  # bootsnap and msgpack. `rails --version` boots Bundler against the lock.
  rails-env =
    pkgs.runCommand "test-rails-env"
      {
        nativeBuildInputs = [
          rails.env
          rails.wrappedRuby
        ];
      }
      ''
        cp -r ${../examples/rails} project
        chmod -R u+w project
        cd project
        bundle exec rails --version | grep 'Rails 8'
        ruby -e 'require "bundler/setup"; require "sqlite3"; require "nokogiri"; puts SQLite3::SQLITE_VERSION'
        touch $out
      '';

  formatting = (import ./formatter.nix { inherit pkgs; }).check self;
}
