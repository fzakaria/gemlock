# Assertion helpers for the eval tests. A test file returns a summary only
# after every assertion holds, so `nix eval` on it is the test run and the
# derivation in nix/checks.nix just writes the summary out.
let
  inherit (builtins) toJSON all length;
in
rec {
  # One named equality. The message carries both sides as JSON so a failing
  # check reads as a diff rather than a stack of thunks.
  assertEq =
    name: expected: actual:
    if expected == actual then
      true
    else
      throw "${name}: expected ${toJSON expected}, got ${toJSON actual}";

  # A named boolean.
  assertTrue = name: cond: if cond then true else throw "${name}: expected true";

  # Force a list of assertions and report how many held.
  summarize =
    checks:
    assert all (c: c) checks;
    {
      passed = length checks;
    };
}
