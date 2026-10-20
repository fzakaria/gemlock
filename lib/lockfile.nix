# A parser for Gemfile.lock, written against the format Bundler writes
# rather than a grammar: the file is line-oriented and indentation is the
# only structure. Two spaces is an option or a list entry, four is a spec,
# six is a spec's dependency. Built on builtins only.
#
# The result:
#
#   {
#     sources      = [ { type = "gem" | "git" | "path"; ...; specs = [ spec ]; } ];
#     specs        = [ spec ];            # every spec, with its source attached
#     platforms    = [ "ruby" "x86_64-linux" ... ];
#     dependencies = [ { name; requirement; pinned; } ];   # the DEPENDENCIES roots
#     checksums    = { "<name>-<version>[-<platform>]" = "<sha256 hex>"; };
#     rubyVersion  = null | { engine; version; raw; };
#     bundledWith  = null | "2.6.9";
#   }
#
#   spec = { name; version; platform; fullName; dependencies = [ { name; requirement; } ];
#            source; sha256 = hex | null; }
#
# A spec's `platform` is "ruby" unless the version carried a suffix:
# `nokogiri (1.19.4-x86_64-linux-gnu)` is version 1.19.4 on x86_64-linux-gnu.
# Gem::Version never contains a hyphen (a `-` in a version becomes `.pre.`),
# so the first hyphen always starts the platform.
content:
let
  inherit (builtins)
    match
    split
    filter
    isString
    foldl'
    head
    tail
    length
    elemAt
    genList
    stringLength
    substring
    listToAttrs
    ;

  lines = filter isString (split "\n" content);

  reverse =
    l:
    let
      n = length l;
    in
    genList (i: elemAt l (n - 1 - i)) n;

  stripTrailingSlash = s: if match ".*/" s != null then substring 0 (stringLength s - 1) s else s;

  splitVersion =
    v:
    let
      m = match "([^-]+)-(.*)" v;
    in
    if m == null then
      {
        version = v;
        platform = "ruby";
      }
    else
      {
        version = elemAt m 0;
        platform = elemAt m 1;
      };

  mkSpec =
    name: versionAndPlatform:
    splitVersion versionAndPlatform
    // {
      inherit name;
      fullName = "${name}-${versionAndPlatform}";
      dependencies = [ ];
    };

  # Section headers Bundler writes. Anything else at column zero is a format
  # this parser has not seen, and that is worth an error rather than a guess.
  sourceSections = [
    "GEM"
    "GIT"
    "PATH"
  ];
  listSections = [
    "PLATFORMS"
    "DEPENDENCIES"
    "CHECKSUMS"
    "RUBY VERSION"
    "BUNDLED WITH"
  ];
  lower = builtins.replaceStrings [ "GEM" "GIT" "PATH" ] [ "gem" "git" "path" ];

  # Specs and their dependencies are prepended as they are read, and turned
  # the right way round when the source is closed.
  closeSource =
    state:
    if state.source == null then
      state
    else
      state
      // {
        source = null;
        sources = state.sources ++ [
          (
            state.source
            // {
              specs = map (s: s // { dependencies = reverse s.dependencies; }) (reverse state.source.specs);
            }
          )
        ];
      };

  openSource =
    state: type:
    state
    // {
      source = {
        inherit type;
        specs = [ ];
      }
      // (if type == "gem" then { remotes = [ ]; } else { });
    };

  # One line, folded into the state.
  step =
    state: rawLine:
    let
      line = head (match "([^\r]*)\r?" rawLine);
      header = match "([A-Z][A-Z ]*)" line;
      option = match "  ([a-z]+):( (.*))?" line;
      specLine = match "    ([^ ]+) \\(([^)]+)\\)" line;
      depLine = match "      ([^ ]+)( \\((.*)\\))?" line;
      rootLine = match "  ([^ !]+)( \\((.*)\\))?(!)?" line;
      checksumLine = match "  ([^ ]+) \\(([^)]+)\\)( sha256=([0-9a-f]+))?" line;
      entry = match "  ([^ ].*)" line;
      trailer = match "   (.*)" line;
      section = state.section;
      src = state.source;
    in
    if line == "" then
      state

    # A new section. Close whatever source was open.
    else if header != null then
      let
        name = head header;
        closed = closeSource state // {
          section = name;
        };
      in
      if builtins.elem name sourceSections then
        openSource closed (lower name)
      else if builtins.elem name listSections then
        closed
      else if name == "PLUGIN SOURCE" then
        throw "gemlock: this Gemfile.lock has a PLUGIN SOURCE section, which gemlock cannot fetch from"
      else
        throw "gemlock: unknown Gemfile.lock section '${name}'"

    # Inside GEM, GIT or PATH.
    else if src != null then
      if specLine != null then
        state
        // {
          source = src // {
            specs = [ (mkSpec (elemAt specLine 0) (elemAt specLine 1)) ] ++ src.specs;
          };
        }
      else if depLine != null then
        let
          spec = head src.specs;
          dep = {
            name = elemAt depLine 0;
            requirement = elemAt depLine 2;
          };
        in
        state
        // {
          source = src // {
            specs = [ (spec // { dependencies = [ dep ] ++ spec.dependencies; }) ] ++ tail src.specs;
          };
        }
      else if option != null then
        let
          key = elemAt option 0;
          value = elemAt option 2;
        in
        if key == "specs" then
          state
        else if key == "remote" && src.type == "gem" then
          # Bundler tries the last-declared remote first, and writes them to
          # the file first-declared first. Prepending keeps Bundler's order.
          state
          // {
            source = src // {
              remotes = [ (stripTrailingSlash value) ] ++ src.remotes;
            };
          }
        else if key == "submodules" then
          state
          // {
            source = src // {
              submodules = value == "true";
            };
          }
        else
          state
          // {
            source = src // {
              ${key} = value;
            };
          }
      else
        throw "gemlock: cannot read lockfile line '${line}' in section ${section}"

    # The flat sections.
    else if section == "PLATFORMS" && entry != null then
      state
      // {
        platforms = state.platforms ++ [ (head entry) ];
      }
    else if section == "DEPENDENCIES" && rootLine != null then
      state
      // {
        dependencies = state.dependencies ++ [
          {
            name = elemAt rootLine 0;
            requirement = elemAt rootLine 2;
            pinned = elemAt rootLine 3 != null;
          }
        ];
      }
    else if section == "CHECKSUMS" && checksumLine != null then
      let
        hash = elemAt checksumLine 3;
      in
      if hash == null then
        state
      else
        state
        // {
          checksums = state.checksums // {
            "${elemAt checksumLine 0}-${elemAt checksumLine 1}" = hash;
          };
        }
    else if section == "RUBY VERSION" && trailer != null then
      let
        raw = head trailer;
        parsed = match "([a-z]+) ([0-9.]+).*" raw;
      in
      state
      // {
        rubyVersion = {
          inherit raw;
          engine = if parsed == null then null else elemAt parsed 0;
          version = if parsed == null then null else elemAt parsed 1;
        };
      }
    else if section == "BUNDLED WITH" && trailer != null then
      state
      // {
        bundledWith = head trailer;
      }
    else
      throw "gemlock: cannot read lockfile line '${line}' in section ${toString section}";

  initial = {
    section = null;
    source = null;
    sources = [ ];
    platforms = [ ];
    dependencies = [ ];
    checksums = { };
    rubyVersion = null;
    bundledWith = null;
  };

  final = closeSource (foldl' step initial lines);

  specs = builtins.concatMap (
    source:
    map (
      spec:
      spec
      // {
        source = removeAttrs source [ "specs" ];
        sha256 = final.checksums.${spec.fullName} or null;
      }
    ) source.specs
  ) final.sources;
in
(removeAttrs final [
  "section"
  "source"
])
// {
  inherit specs;
}
