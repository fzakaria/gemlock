# One derivation per resolved gem, as a scope (lib.makeScope), so that
# gems.nokogiri is a package like any other: overrideAttrs works on it, and
# `overrides` is an ordinary overlay applied with overrideScope.
#
# The build itself is nixpkgs' buildRubyGem. It already knows how to
# install a .gem, how to lay a git checkout out the way Bundler expects
# under bundler/gems/, and how to write binstubs. What gemlock decides is
# the input: the hash straight from the lock's CHECKSUMS, the platform
# variant resolve.nix chose, and for a precompiled gem on Linux the ELF
# patching that makes a binary built against /lib64 run from the store.
{
  pkgs,
  src,
  ruby,
  resolved,
  overrides,
  sources,
}:
let
  inherit (pkgs) lib stdenv;
  inherit (builtins) convertHash;

  # nixpkgs' per-gem build fixes (libxml2 for nokogiri from source, libpq
  # for pg, ...). They assume a source build, so a precompiled variant
  # skips them.
  gemConfig = pkgs.defaultGemConfig;

  sriHash =
    spec:
    if spec.sha256 == null then
      throw ''
        gemlock: Gemfile.lock has no checksum for ${spec.fullName}.
        Add them with `nix run .#lock`, or by hand: bundle lock --add-checksums''
    else
      convertHash {
        hash = spec.sha256;
        hashAlgo = "sha256";
        toHashFormat = "sri";
      };

  # builtins.fetchGit with a full commit is pure. The ref the lock recorded
  # narrows what has to be fetched; without one, every ref is on the table.
  fetchGitSource =
    source:
    builtins.fetchGit (
      {
        url = source.remote;
        rev = source.revision;
        shallow = true;
        submodules = source.submodules or false;
      }
      // (
        if source ? tag then
          { ref = "refs/tags/${source.tag}"; }
        else if source ? branch then
          { ref = source.branch; }
        else
          { allRefs = true; }
      )
    );

  bySourceType =
    name: spec:
    let
      source = spec.source;
    in
    if source.type == "gem" then
      {
        type = "gem";
        source = {
          remotes = source.remotes;
          sha256 = sriHash spec;
        };
      }
    else if source.type == "git" then
      {
        type = "git";
        source = {
          url = source.remote;
          rev = source.revision;
        };
        src = sources.${name} or (fetchGitSource source);
      }
    else
      # A path gem: buildRubyGem's "url" type installs an unpacked tree
      # through Bundler::Source::Path, which is what this is.
      {
        type = "url";
        src = sources.${name} or (src + "/${source.remote}");
      };

  mkGem =
    final: name: spec:
    let
      precompiled = spec.platform != "ruby";
      base = {
        gemName = name;
        inherit (spec) version platform;
        inherit ruby;
        gemPath = map (d: final.${d.name}) (
          builtins.filter (d: d.name != "bundler" && resolved.gems ? ${d.name}) spec.dependencies
        );
      }
      // bySourceType name spec;
      withPatchelf = base // {
        nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
        # What a precompiled extension or binary usually links beyond libc.
        buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
          stdenv.cc.cc.lib
          pkgs.zlib
        ];
      };
      withConfig = if gemConfig ? ${name} then base // gemConfig.${name} base else base;
    in
    pkgs.buildRubyGem (if precompiled then withPatchelf else withConfig);

  scope = lib.makeScope pkgs.newScope (final: lib.mapAttrs (mkGem final) resolved.gems);
in
scope.overrideScope overrides
