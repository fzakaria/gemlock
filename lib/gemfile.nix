# Which Bundler groups each gem in a Gemfile belongs to. The lockfile does
# not record groups, and the Gemfile is Ruby, so this reads the two forms
# that carry group information and nothing else:
#
#   group :development, :test do ... end
#   gem "x", group: :tools            # also groups: [...] and :group => ...
#
# Other blocks (`platforms`, `source`, `path`, `install_if`) are tracked
# only so their `end` lines are matched up. A gem this cannot see, for
# example one declared by `gemspec` or `eval_gemfile`, is simply absent
# and is treated as "default" by the caller. Returns { <gem> = [ group ]; }.
content:
let
  inherit (builtins)
    match
    split
    filter
    isString
    isList
    foldl'
    head
    tail
    length
    elemAt
    concatMap
    concatLists
    elem
    ;

  lines = filter isString (split "\n" content);

  # Every :symbol, "string" or 'string' token in a piece of argument text.
  names =
    text:
    map head (filter isList (split "[:\"']([A-Za-z0-9_-]+)[\"']?" text));

  unique = foldl' (acc: x: if elem x acc then acc else acc ++ [ x ]) [ ];

  step =
    state: rawLine:
    let
      # Drop a trailing comment and surrounding whitespace.
      line = head (match " *([^#]*[^# ])?.*" (head (match "([^\r]*)\r?" rawLine)));
      text = if line == null then "" else line;
      groupBlock = match "group[ (]+(.*[^ )])[ )]*do( *\\|.*\\|)? *" text;
      otherBlock = match ".*[ )]do( *\\|.*\\|)? *" text;
      endLine = match "end( .*)?" text;
      gemLine = match "gem +[\"']([^\"']+)[\"'](.*)" text;
      blockGroups = concatLists (filter (f: f != null) state.stack);
    in
    if text == "" then
      state
    else if groupBlock != null then
      state // {
        stack = [ (names (head groupBlock)) ] ++ state.stack;
      }
    else if otherBlock != null then
      state // {
        stack = [ null ] ++ state.stack;
      }
    else if endLine != null then
      state // {
        stack = if state.stack == [ ] then [ ] else tail state.stack;
      }
    else if gemLine != null then
      let
        name = head gemLine;
        rest = elemAt gemLine 1;
        keyword = match ".*(:groups? *=> *|[ ,]groups?: *)([[][A-Za-z0-9_,:\"' -]*[]]|:[A-Za-z0-9_-]+|[\"'][A-Za-z0-9_-]+[\"']).*" rest;
        keywordGroups = if keyword == null then [ ] else names (elemAt keyword 1);
        groups = unique (blockGroups ++ keywordGroups);
      in
      state // {
        groups = state.groups // {
          ${name} = unique ((state.groups.${name} or [ ]) ++ (if groups == [ ] then [ "default" ] else groups));
        };
      }
    else
      state;

  final = foldl' step {
    stack = [ ];
    groups = { };
  } lines;
in
final.groups
