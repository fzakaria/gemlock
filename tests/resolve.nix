# Variant selection and the dependency closure: one spec per gem name, for
# one local platform, reachable from the DEPENDENCIES roots in the wanted
# groups.
{
  gemlock,
  nixpkgs ? null,
}:
let
  inherit (builtins)
    readFile
    attrNames
    length
    tryEval
    hasAttr
    ;
  inherit (import ./lib.nix) assertEq assertTrue summarize;
  inherit (gemlock.lib) parseLockfile parseGemfileGroups resolve;
  inherit (gemlock.lib.platform) parse;

  basic = parseLockfile (readFile ../examples/basic/Gemfile.lock);
  rails = parseLockfile (readFile ../examples/rails/Gemfile.lock);
  railsGroups = parseGemfileGroups (readFile ../examples/rails/Gemfile);

  on =
    local:
    resolve {
      lock = basic;
      local = parse local;
    };
  linux = on "x86_64-linux";
  darwin = on "arm64-darwin23";
  musl = on "aarch64-linux-musl";
  riscv = tryEval (on "riscv64-linux").gems;

  devOnly = resolve {
    lock = basic;
    local = parse "x86_64-linux";
    groups = [ "default" ];
    gemGroups.sorbet-static = [ "development" ];
  };

  railsProd = resolve {
    lock = rails;
    local = parse "x86_64-linux";
    groups = [
      "default"
      "production"
    ];
    gemGroups = railsGroups;
  };
  railsAll = resolve {
    lock = rails;
    local = parse "x86_64-linux";
  };

  # Every example lock has to resolve on every platform `nix run .#lock`
  # asks Bundler for, so a lock that quietly lacks a platform's variants
  # fails here on Linux instead of on the first Mac that evaluates it.
  lockPlatforms = [
    "x86_64-linux"
    "aarch64-linux"
    "arm64-darwin"
    "x86_64-darwin"
  ];
  resolvesEverywhere =
    name: lock:
    map (
      p:
      assertTrue "${name} resolves on ${p}"
        (tryEval (
          attrNames
            (resolve {
              inherit lock;
              local = parse p;
            }).gems
        )).success
    ) lockPlatforms;
in
summarize (
  resolvesEverywhere "basic" basic
  ++ resolvesEverywhere "rails" rails
  ++ [
    (assertEq "linux: five gems" 5 (length (attrNames linux.gems)))
    (assertEq "linux: nokogiri variant" "x86_64-linux-gnu" linux.gems.nokogiri.platform)
    (assertEq "linux: sorbet variant" "x86_64-linux" linux.gems.sorbet-static.platform)
    (assertEq "linux: racc pulled in by nokogiri" "1.8.1" linux.gems.racc.version)
    (assertEq "linux: rack from git" "git" linux.gems.rack.source.type)

    (assertEq "darwin: nokogiri variant" "arm64-darwin" darwin.gems.nokogiri.platform)
    (assertEq "darwin: sorbet variant" "universal-darwin" darwin.gems.sorbet-static.platform)

    (assertEq "musl: nokogiri variant" "aarch64-linux-musl" musl.gems.nokogiri.platform)
    (assertEq "musl: sorbet variant" "aarch64-linux" musl.gems.sorbet-static.platform)

    # A gem the lock has no usable variant for is an error, not a silent gap.
    (assertEq "riscv: no sorbet variant is an error" false riscv.success)

    (assertEq "groups: sorbet excluded" false (hasAttr "sorbet-static" devOnly.gems))
    (assertEq "groups: four gems" 4 (length (attrNames devOnly.gems)))

    (assertEq "rails: everything" 112 (length (attrNames railsAll.gems)))
    (assertTrue "rails prod: no capybara" (!hasAttr "capybara" railsProd.gems))
    (assertTrue "rails prod: no debug" (!hasAttr "debug" railsProd.gems))
    (assertTrue "rails prod: rails and puma" (
      hasAttr "rails" railsProd.gems && hasAttr "puma" railsProd.gems
    ))
    (assertEq "rails prod: sqlite3 precompiled" "x86_64-linux-gnu" railsProd.gems.sqlite3.platform)
    (assertTrue "rails prod: fewer gems" (length (attrNames railsProd.gems) < 112))
  ]
)
