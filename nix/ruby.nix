# Which Ruby a project gets. In order: the `ruby` the caller passed, the
# project's .ruby-version, the RUBY VERSION section of the lock, and
# finally pkgs.ruby. A version is mapped to nixpkgs' ruby_<major>_<minor>;
# nixpkgs ships a few of those, and anything else has to be passed in,
# for example from nixpkgs-ruby.
{
  pkgs,
  src,
  lock,
  requested,
}:
let
  inherit (pkgs) lib;
  inherit (builtins) pathExists readFile match;

  versionFile = src + "/.ruby-version";
  fromFile =
    if pathExists versionFile then
      let
        # "3.4.1", "ruby-3.4.1" or "ruby 3.4.1", with a trailing newline.
        m = match "[ \n]*(ruby[- ])?([0-9]+\\.[0-9]+)(\\.[0-9A-Za-z.-]+)?[ \n]*" (readFile versionFile);
      in
      if m == null then null else builtins.elemAt m 1
    else
      null;

  fromLock =
    if
      lock.rubyVersion != null && lock.rubyVersion.engine == "ruby" && lock.rubyVersion.version != null
    then
      lib.versions.majorMinor lock.rubyVersion.version
    else
      null;

  wanted = if fromFile != null then fromFile else fromLock;

  attrName =
    v:
    let
      parts = lib.splitString "." v;
    in
    "ruby_${builtins.elemAt parts 0}_${builtins.elemAt parts 1}";

  chosen =
    if requested != null then
      requested
    else if wanted == null then
      pkgs.ruby
    else if pkgs ? ${attrName wanted} then
      pkgs.${attrName wanted}
    else
      throw ''
        gemlock: the project wants Ruby ${wanted} (${
          if fromFile != null then ".ruby-version" else "RUBY VERSION in Gemfile.lock"
        }) and nixpkgs has no ${attrName wanted}.
        Pass one in: loadBundle { ruby = <a ruby ${wanted} derivation>; ... }'';

  chosenMajorMinor = lib.versions.majorMinor chosen.version;
in
# Gems install under lib/ruby/gems/<major>.<minor>.0 and extensions build
# against that ABI, so a lock resolved under a different major.minor
# describes a different environment.
if fromLock != null && fromLock != chosenMajorMinor then
  throw ''
    gemlock: Gemfile.lock was resolved with Ruby ${lock.rubyVersion.version} and this bundle is built with Ruby ${chosen.version}.
    Pass a matching ruby to loadBundle, or relock under Ruby ${chosenMajorMinor} with `nix run .#lock`.''
else
  chosen
