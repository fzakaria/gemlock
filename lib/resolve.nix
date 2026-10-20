# From a parsed lockfile to the one spec per gem that this host will get.
#
# A lock lists a gem once per platform it was resolved for, so the first
# job is choosing a variant: the one Bundler would install here, by the
# rules in platform.nix. The second is the closure: start from the
# DEPENDENCIES roots in the wanted groups and follow the chosen variants'
# dependencies, because those differ by variant (the source build of
# nokogiri needs mini_portile2; the precompiled one does not).
#
# Returns { gems = { <name> = spec; }; roots = [ name ]; }. A root with no
# variant for this platform is an error, since Bundler would refuse the
# same install, and the fix is a relock with the platform added.
let
  platform = import ./platform.nix;
  inherit (builtins)
    filter
    map
    elem
    groupBy
    mapAttrs
    hasAttr
    attrNames
    concatMap
    foldl'
    length
    listToAttrs
    concatStringsSep
    ;
in
{
  lock,
  # { cpu; os; version; } from platform.parse or platform.fromHostPlatform.
  local,
  # Bundler groups to install, or null for every gem in the lock.
  groups ? null,
  # { <gem> = [ group ]; } as lib/gemfile.nix reads it. A gem not listed
  # is in "default".
  gemGroups ? { },
}:
let
  byName = groupBy (s: s.name) lock.specs;

  # Whether PLATFORMS already covers the local platform. Then the missing
  # variant is not a forgotten --add-platform: Bundler lists a platform
  # and still writes none of its variants when one gem has no build for it
  # that the locking Ruby accepts (Bundler::SpecSet#complete_platform).
  listed = local: builtins.any (p: p != "ruby" && platform.matches local p) lock.platforms;
  skippedHint = ''
    PLATFORMS lists it, so Bundler skipped the platform while locking. That happens,
    silently, when one gem's precompiled build for the platform does not accept the
    Ruby that ran `bundle lock`. Run `nix run .#lock` again: it removes and re-adds
    the platform, and names the gem if Bundler still skips it. See docs/using.md, "Lock".'';

  choose =
    name: variants:
    let
      platforms = map (s: s.platform) variants;
      chosen = platform.best local platforms;
    in
    if chosen == null then
      throw ''
        gemlock: no variant of '${name}' in Gemfile.lock runs on ${platform.toString local}.
        The lock has it for: ${concatStringsSep ", " platforms}.
        ${
          if listed local then
            skippedHint
          else
            "Add this platform with: nix run .#lock -- --add-platform ${platform.toString local}"
        }''
    else
      builtins.head (filter (s: s.platform == chosen) variants);

  # Lazy, so a variant is chosen only for gems that are reached.
  chosenByName = mapAttrs choose byName;

  inGroups =
    name: groups == null || builtins.any (g: elem g groups) (gemGroups.${name} or [ "default" ]);

  # A root with no spec at all is one Bundler left out of the lock on
  # purpose: `gem "tzinfo-data", platforms: [:windows]` on a lock with no
  # Windows platform. Those are skipped the way Bundler skips them.
  roots = filter (n: inGroups n && hasAttr n byName) (map (d: d.name) lock.dependencies);

  # bundler is a dependency of many gems and never a spec in the lock.
  depsOf =
    name:
    if name == "bundler" then
      [ ]
    else if !hasAttr name byName then
      throw "gemlock: '${name}' is depended on but has no entry in Gemfile.lock; run `nix run .#lock`"
    else
      filter (d: d != "bundler") (map (d: d.name) chosenByName.${name}.dependencies);

  unique = foldl' (acc: x: if elem x acc then acc else acc ++ [ x ]) [ ];
  expand = names: unique (names ++ concatMap depsOf names);
  closure =
    names:
    let
      next = expand names;
    in
    if length next == length names then names else closure next;

  reached = closure (filter (n: n != "bundler") roots);
in
{
  inherit roots;
  gems = listToAttrs (
    map (name: {
      inherit name;
      value = chosenByName.${name};
    }) reached
  );
}
