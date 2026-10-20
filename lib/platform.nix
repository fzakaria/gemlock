# Gem platforms, the way RubyGems reads them. A platform string such as
# `x86_64-linux-gnu` or `arm64-darwin-23` is parsed into { cpu; os; version; }
# with the rules of Gem::Platform#initialize, and a spec's platform is
# matched against the local one with the rules of Gem::Platform#===. Both
# are ported line for line from rubygems/platform.rb, and tests/platform.nix
# holds the truth table RubyGems produced for the same inputs.
#
# Among several matching variants, `best` picks the one Bundler would:
# the exact local platform first, then the closest by os, cpu and version,
# with the pure "ruby" platform last (Bundler::GemHelpers::PlatformMatch).
let
  inherit (builtins)
    match
    split
    filter
    isString
    length
    head
    tail
    elemAt
    elem
    foldl'
    concatStringsSep
    ;

  isNumber = s: match "[0-9]+(\\.[0-9]+)?" s != null;
  hasPrefix = p: s: s != null && match "${p}.*" s != null;
  last = l: elemAt l (length l - 1);
  init = l: builtins.genList (i: elemAt l i) (length l - 1);
  capture = i: m: if m == null then null else elemAt m i;

  # The os half of the table in Gem::Platform#initialize. The input is the
  # os token alone, so the patterns are anchored where Ruby's are not.
  osAndVersion =
    tok:
    let
      try = re: match re tok;
    in
    if try "aix([0-9]+)?" != null then
      [ "aix" (capture 0 (try "aix([0-9]+)?")) ]
    else if try ".*cygwin.*" != null then
      [ "cygwin" null ]
    else if try "darwin([0-9]+)?" != null then
      [ "darwin" (capture 0 (try "darwin([0-9]+)?")) ]
    else if tok == "macruby" then
      [ "macruby" null ]
    else if try "freebsd([0-9]+)?" != null then
      [ "freebsd" (capture 0 (try "freebsd([0-9]+)?")) ]
    else if tok == "java" || tok == "jruby" then
      [ "java" null ]
    else if try "java([0-9.]*)" != null then
      [ "java" (capture 0 (try "java([0-9.]*)")) ]
    else if try "dalvik([0-9]+)?" != null then
      [ "dalvik" (capture 0 (try "dalvik([0-9]+)?")) ]
    else if tok == "dotnet" then
      [ "dotnet" null ]
    else if try "dotnet([0-9.]*)" != null then
      [ "dotnet" (capture 0 (try "dotnet([0-9.]*)")) ]
    else if try "linux-?([A-Za-z0-9_]+)?" != null then
      [ "linux" (capture 0 (try "linux-?([A-Za-z0-9_]+)?")) ]
    else if try ".*mingw32.*" != null then
      [ "mingw32" null ]
    else if try "mingw-?([A-Za-z0-9_]+)?" != null then
      [ "mingw" (capture 0 (try "mingw-?([A-Za-z0-9_]+)?")) ]
    else if try "(mswin[0-9]+)(_([0-9]+))?" != null then
      [ (capture 0 (try "(mswin[0-9]+)(_([0-9]+))?")) (capture 2 (try "(mswin[0-9]+)(_([0-9]+))?")) ]
    else if try ".*netbsdelf.*" != null then
      [ "netbsdelf" null ]
    else if try "openbsd([0-9]+\\.[0-9]+)?" != null then
      [ "openbsd" (capture 0 (try "openbsd([0-9]+\\.[0-9]+)?")) ]
    else if try "solaris([0-9]+\\.[0-9]+)?" != null then
      [ "solaris" (capture 0 (try "solaris([0-9]+\\.[0-9]+)?")) ]
    else if try ".*wasi.*" != null then
      [ "wasi" null ]
    else
      [ "unknown" null ];

  parse =
    str:
    let
      raw = filter isString (split "-" str);
      # `x86_64-linux-gnu` is two parts, not three: a trailing token that is
      # not a version number belongs to the os.
      parts =
        if length raw > 2 && !isNumber (last raw) then
          init (init raw) ++ [ "${elemAt raw (length raw - 2)}-${last raw}" ]
        else
          raw;
      cpuTok = head parts;
      rest = tail parts;
      cpu = if match "i[0-9]86" cpuTok != null then "x86" else cpuTok;
    in
    # `arm64-darwin-23` on the command line: os and version spelled apart.
    if length rest == 2 && isNumber (last rest) then
      {
        inherit cpu;
        os = head rest;
        version = last rest;
      }
    else
      let
        osTok = if rest == [ ] then cpuTok else head rest;
        ov = osAndVersion osTok;
        os = head ov;
      in
      {
        # A bare os such as `java`: no cpu at all.
        cpu = if rest == [ ] then (if match "mswin.*32" os != null then "x86" else null) else cpu;
        inherit os;
        version = elemAt ov 1;
      };

  # Gem::Platform#normalized_linux_version: drop a leading `gnu` and a
  # trailing `eabi` or `eabihf`, and nothing left means no version.
  normalizedLinuxVersion =
    v:
    if v == null then
      null
    else
      let
        noGnu = capture 1 (match "(gnu)?(.*)" v);
        abi = match "(.*)eabi(hf)?" noGnu;
        stripped = if abi == null then noGnu else head abi;
      in
      if stripped == "" then null else stripped;

  # Gem::Platform#===: does a spec on platform `spec` run on `local`?
  matches =
    local: spec:
    if spec == "ruby" then
      true
    else
      let
        s = parse spec;
        o = local;
        sv = if s.version == null then "" else s.version;
        mingwUniversal =
          (s.cpu == "universal" || o.cpu == "universal") && hasPrefix "mingw" s.os && hasPrefix "mingw" o.os;
        cpuOk =
          s.cpu == null
          || s.cpu == "universal"
          || o.cpu == null
          || o.cpu == "universal"
          || s.cpu == o.cpu
          || (s.cpu == "arm" && hasPrefix "armv" o.cpu);
        osOk = s.os == o.os;
        versionOk =
          (s.os != "linux" && (s.version == null || o.version == null))
          || (
            s.os == "linux"
            && (
              normalizedLinuxVersion s.version == normalizedLinuxVersion o.version
              || elem o.version [
                "musl${sv}"
                "musleabi${sv}"
                "musleabihf${sv}"
              ]
            )
          )
          || s.version == o.version;
      in
      mingwUniversal || (cpuOk && osOk && versionOk);

  # Bundler::GemHelpers::PlatformMatch.specificity_score. Lower is better:
  # the exact local platform scores -1, "ruby" a million, and anything
  # else a small sum over os, cpu and version.
  specificity =
    local: spec:
    if spec == "ruby" then
      1000000
    else
      let
        s = parse spec;
        o = local;
      in
      if s == o then
        -1
      else
        (if s.os == o.os then 0 else 1)
        + 10 * (
          if s.cpu == o.cpu || (s.cpu == "arm" && hasPrefix "arm" o.cpu) then
            0
          else if s.cpu == null || s.cpu == "universal" then
            1
          else
            2
        )
        + 100 * (
          if s.version == o.version then
            0
          else if s.version == null then
            1
          else
            2
        );

  # The platform to build for out of a list of candidate platform strings,
  # or null when none of them runs here. Ties keep the earlier candidate.
  best =
    local: candidates:
    foldl' (
      acc: spec:
      if !matches local spec then
        acc
      else if acc == null || specificity local spec < specificity local acc then
        spec
      else
        acc
    ) null candidates;

  # The platform a nixpkgs-built Ruby reports as Gem::Platform.local on a
  # host, from lib.systems.elaborate's view of that host. Darwin gets no
  # version on purpose: the kernel major baked into a Ruby build is not
  # something worth refusing a gem over, and a missing version matches any.
  fromHostPlatform =
    hp:
    let
      cpuName = hp.parsed.cpu.name;
      abi = hp.parsed.abi.name;
      eabi =
        if match ".*eabihf" abi != null then
          "eabihf"
        else if match ".*eabi" abi != null then
          "eabi"
        else
          "";
    in
    {
      cpu =
        if hp.isDarwin && cpuName == "aarch64" then
          "arm64"
        else if match "i[0-9]86" cpuName != null then
          "x86"
        else
          cpuName;
      os =
        if hp.isDarwin then
          "darwin"
        else if hp.isLinux then
          "linux"
        else if hp.isFreeBSD then
          "freebsd"
        else if hp.isWindows then
          "mingw"
        else
          hp.parsed.kernel.name;
      version =
        if !hp.isLinux then
          null
        else if hp.isMusl then
          "musl${eabi}"
        else if eabi != "" then
          eabi
        else
          null;
    };

  # Back to a string, for messages.
  toString' =
    p:
    concatStringsSep "-" (
      filter (x: x != null) [
        p.cpu
        p.os
        p.version
      ]
    );
in
{
  inherit
    parse
    matches
    specificity
    best
    fromHostPlatform
    ;
  toString = toString';
}
