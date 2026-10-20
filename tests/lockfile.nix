# The lockfile parser, against the two example locks and the Gemfile.lock
# files committed to nixpkgs. The nixpkgs locks predate Bundler's CHECKSUMS
# section, which is what makes them a good corpus: the parser has to read
# them without one.
{
  gemlock,
  nixpkgs ? null,
}:
let
  inherit (builtins)
    length
    filter
    head
    readFile
    elem
    attrNames
    all
    ;
  inherit (import ./lib.nix) assertEq assertTrue summarize;
  inherit (gemlock.lib) parseLockfile;

  basic = parseLockfile (readFile ../examples/basic/Gemfile.lock);
  rails = parseLockfile (readFile ../examples/rails/Gemfile.lock);

  byFullName = lock: name: head (filter (s: s.fullName == name) lock.specs);
  nokogiri = byFullName basic "nokogiri-1.19.4-x86_64-linux-gnu";
  rack = byFullName basic "rack-3.1.8";
  rootDep = lock: name: head (filter (d: d.name == name) lock.dependencies);

  # Every Gemfile.lock in the nixpkgs tree, parsed. The list is committed so
  # the check reads 134 known files instead of walking the whole tree.
  corpus =
    if nixpkgs == null then
      [ ]
    else
      filter (p: p != "") (filter builtins.isString (builtins.split "\n" (readFile ./fixtures/nixpkgs-lockfiles.txt)));
  corpusParses = map (
    rel:
    let
      lock = parseLockfile (readFile (nixpkgs + "/${rel}"));
    in
    assertTrue "${rel}: has specs" (length lock.specs > 0)
  ) corpus;
in
summarize (
  [
    # Sources, in file order, each knowing its own type and options.
    (assertEq "basic: two sources" 2 (length basic.sources))
    (assertEq "basic: git source" {
      type = "git";
      remote = "https://github.com/rack/rack";
      revision = "09f2f66ac1bb392ae58fd531dcb0acd01c9680be";
      tag = "v3.1.8";
    } (removeAttrs (head basic.sources) [ "specs" ]))
    (assertEq "basic: gem source remotes" [ "https://rubygems.org" ] (builtins.elemAt basic.sources 1).remotes)

    # A platform-qualified spec is split into version and platform, keeps its
    # dependency requirements, and carries its checksum from CHECKSUMS.
    (assertEq "basic: twelve specs" 12 (length basic.specs))
    (assertEq "basic: nokogiri spec" {
      name = "nokogiri";
      version = "1.19.4";
      platform = "x86_64-linux-gnu";
      fullName = "nokogiri-1.19.4-x86_64-linux-gnu";
      dependencies = [
        {
          name = "racc";
          requirement = "~> 1.4";
        }
      ];
      sha256 = "379fae440b28915e3f19d752ce2dcf8465ed2b2fbefd2a7ca0dd497bc981a06a";
    } (removeAttrs nokogiri [ "source" ]))
    (assertEq "basic: nokogiri source type" "gem" nokogiri.source.type)
    (assertEq "basic: rack platform" "ruby" rack.platform)
    (assertEq "basic: rack has no checksum" null rack.sha256)
    (assertEq "basic: rack source" "git" rack.source.type)

    # The PLATFORMS section, verbatim.
    (assertEq "basic: ten platforms" 10 (length basic.platforms))
    (assertTrue "basic: musl platform listed" (elem "x86_64-linux-musl" basic.platforms))

    # DEPENDENCIES: the roots, with their requirement and the `!` that marks
    # a gem pinned to a git or path source.
    (assertEq "basic: four roots" 4 (length basic.dependencies))
    (assertEq "basic: rack root is pinned" {
      name = "rack";
      requirement = null;
      pinned = true;
    } (rootDep basic "rack"))
    (assertEq "basic: rake root" {
      name = "rake";
      requirement = null;
      pinned = false;
    } (rootDep basic "rake"))

    # Trailer sections.
    (assertEq "basic: no ruby version" null basic.rubyVersion)
    (assertEq "basic: bundled with" "2.6.9" basic.bundledWith)
    (assertEq "basic: eleven checksums" 11 (length (attrNames basic.checksums)))

    # The Rails 8 lock: bigger, with requirement ranges and no git sources.
    (assertEq "rails: spec count" 138 (length rails.specs))
    (assertEq "rails: root count" 22 (length rails.dependencies))
    (assertEq "rails: rails requirement" "~> 8.0" (rootDep rails "rails").requirement)
    (assertEq "rails: sqlite3 requirement" ">= 2.1" (rootDep rails "sqlite3").requirement)
    (assertTrue "rails: every gem spec has a checksum" (
      all (s: s.sha256 != null) (filter (s: s.source.type == "gem") rails.specs)
    ))
  ]
  ++ corpusParses
)
