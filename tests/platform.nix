# Gem platform matching, checked against RubyGems itself. The fixture is
# the output of tests/fixtures/platforms.rb under RubyGems 3.7: for each
# local platform, how Gem::Platform.new parses it and which of a list of
# spec platforms Gem::Platform#=== accepts. The Nix port has to agree on
# every row.
{
  gemlock,
  nixpkgs ? null,
}:
let
  inherit (builtins)
    fromJSON
    readFile
    filter
    attrNames
    concatMap
    ;
  inherit (import ./lib.nix) assertEq summarize;
  inherit (gemlock.lib.platform)
    parse
    matches
    fromHostPlatform
    best
    ;

  fixture = fromJSON (readFile ./fixtures/platform-matches.json);
  locals = filter (n: builtins.substring 0 1 n != "_") (attrNames fixture);
  # The same list, in the same order, as platforms.rb asked about.
  specs = [
    "ruby"
    "x86_64-linux"
    "x86_64-linux-gnu"
    "x86_64-linux-musl"
    "aarch64-linux"
    "aarch64-linux-gnu"
    "aarch64-linux-musl"
    "arm64-darwin"
    "arm64-darwin-22"
    "arm64-darwin-23"
    "x86_64-darwin"
    "x86_64-darwin-20"
    "universal-darwin"
    "universal-darwin-22"
    "arm-linux"
    "arm-linux-gnueabihf"
    "armv7l-linux"
    "x86-linux"
    "x86-linux-gnu"
    "java"
    "universal-java-11"
    "x64-mingw-ucrt"
    "x64-mingw32"
    "x86-mingw32"
    "x86_64-freebsd"
    "x86_64-openbsd"
    "x86_64-linux-android"
    "riscv64-linux"
    "riscv64-linux-gnu"
    "s390x-linux"
    "ppc64le-linux"
    "universal-mingw"
    "x86_64-solaris"
    "sparc-solaris-2.11"
    "loongarch64-linux"
    "powerpc64le-linux"
  ];

  truthTable = concatMap (
    name:
    let
      local = parse name;
      row = fixture.${name};
    in
    [
      (assertEq "parse ${name}" row.parsed [
        local.cpu
        local.os
        local.version
      ])
      (assertEq "matches for ${name}" row.matches (filter (matches local) specs))
    ]
  ) locals;

  # nixpkgs host platforms to the platform the nixpkgs Ruby reports.
  elaborate = (import (nixpkgs + "/lib")).systems.elaborate;
  hostRows =
    if nixpkgs == null then
      [ ]
    else
      [
        (assertEq "host x86_64-linux" {
          cpu = "x86_64";
          os = "linux";
          version = null;
        } (fromHostPlatform (elaborate "x86_64-linux")))
        (assertEq "host aarch64-linux" {
          cpu = "aarch64";
          os = "linux";
          version = null;
        } (fromHostPlatform (elaborate "aarch64-linux")))
        (assertEq "host x86_64-linux-musl" {
          cpu = "x86_64";
          os = "linux";
          version = "musl";
        } (fromHostPlatform (elaborate "x86_64-unknown-linux-musl")))
        (assertEq "host aarch64-darwin" {
          cpu = "arm64";
          os = "darwin";
          version = null;
        } (fromHostPlatform (elaborate "aarch64-darwin")))
        (assertEq "host x86_64-darwin" {
          cpu = "x86_64";
          os = "darwin";
          version = null;
        } (fromHostPlatform (elaborate "x86_64-darwin")))
        (assertEq "host armv7l-linux" {
          cpu = "armv7l";
          os = "linux";
          version = "eabihf";
        } (fromHostPlatform (elaborate "armv7l-linux")))
      ];

  # Among several matching variants, Bundler's preference: the exact local
  # platform, then the closest by os, cpu and version, with "ruby" last.
  preference = [
    (assertEq "prefer exact over gnu" "x86_64-linux" (
      best (parse "x86_64-linux") [
        "ruby"
        "x86_64-linux-gnu"
        "x86_64-linux"
      ]
    ))
    (assertEq "prefer gnu over ruby" "x86_64-linux-gnu" (
      best (parse "x86_64-linux") [
        "ruby"
        "x86_64-linux-gnu"
      ]
    ))
    (assertEq "prefer arm64-darwin over universal" "arm64-darwin" (
      best (parse "arm64-darwin23") [
        "universal-darwin"
        "arm64-darwin"
        "ruby"
      ]
    ))
    (assertEq "universal when it is the only native" "universal-darwin" (
      best (parse "arm64-darwin23") [
        "ruby"
        "universal-darwin"
      ]
    ))
    (assertEq "ruby when nothing native matches" "ruby" (
      best (parse "riscv64-linux") [
        "x86_64-linux"
        "ruby"
      ]
    ))
    (assertEq "null when nothing matches" null (
      best (parse "riscv64-linux") [
        "x86_64-linux"
        "arm64-darwin"
      ]
    ))
  ];
in
summarize (truthTable ++ hostRows ++ preference)
