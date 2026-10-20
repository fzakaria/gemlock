# The Gemfile group reader. It sees `group ... do` blocks and the `group:`
# and `groups:` keywords on a `gem` line, and nothing else, which is enough
# for the Gemfile `rails new` writes and most others.
{
  gemlock,
  nixpkgs ? null,
}:
let
  inherit (builtins) readFile;
  inherit (import ./lib.nix) assertEq summarize;
  inherit (gemlock.lib) parseGemfileGroups;

  rails = parseGemfileGroups (readFile ../examples/rails/Gemfile);

  inline = parseGemfileGroups ''
    source "https://rubygems.org"
    gem "plain"
    gem "kw", group: :tools
    gem "kws", groups: [:a, :b]
    gem "rocket", :group => :legacy
    gem 'single', 'ruby', require: false
    group :development do
      gem "dev1"
      platforms :mri do
        gem "dev2"
      end
      source "https://gems.example.com" do
        gem "dev3"
      end
      gem "dev4", group: :extra
    end
    group "test", :ci do
      gem "spec"
    end
    gem "after"
  '';
in
summarize [
  (assertEq "rails: rails is default" [ "default" ] rails.rails)
  (assertEq "rails: bootsnap with require false is default" [ "default" ] rails.bootsnap)
  (assertEq "rails: debug in development and test" [ "development" "test" ] rails.debug)
  (assertEq "rails: web-console in development" [ "development" ] rails.web-console)
  (assertEq "rails: capybara in test" [ "test" ] rails.capybara)
  (assertEq "rails: tzinfo-data with platforms keyword is default" [ "default" ] rails.tzinfo-data)

  (assertEq "inline: plain" [ "default" ] inline.plain)
  (assertEq "inline: group keyword" [ "tools" ] inline.kw)
  (assertEq "inline: groups keyword" [ "a" "b" ] inline.kws)
  (assertEq "inline: hash rocket" [ "legacy" ] inline.rocket)
  (assertEq "inline: version argument" [ "default" ] inline.single)
  (assertEq "inline: inside block" [ "development" ] inline.dev1)
  (assertEq "inline: nested platforms block" [ "development" ] inline.dev2)
  (assertEq "inline: nested source block" [ "development" ] inline.dev3)
  (assertEq "inline: keyword inside block adds" [ "development" "extra" ] inline.dev4)
  (assertEq "inline: string and symbol group names" [ "test" "ci" ] inline.spec)
  (assertEq "inline: block closed" [ "default" ] inline.after)
]
