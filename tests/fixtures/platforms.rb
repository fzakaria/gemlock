# Generates tests/fixtures/platform-matches.json: how RubyGems parses a set
# of local platforms and which spec platforms it accepts for each. Run it
# with the Ruby the tests are meant to agree with:
#
#   ruby tests/fixtures/platforms.rb > tests/fixtures/platform-matches.json

require "rubygems"
require "json"
specs = %w[ruby x86_64-linux x86_64-linux-gnu x86_64-linux-musl aarch64-linux aarch64-linux-gnu aarch64-linux-musl
           arm64-darwin arm64-darwin-22 arm64-darwin-23 x86_64-darwin x86_64-darwin-20 universal-darwin universal-darwin-22
           arm-linux arm-linux-gnueabihf armv7l-linux x86-linux x86-linux-gnu java universal-java-11 x64-mingw-ucrt x64-mingw32
           x86-mingw32 x86_64-freebsd x86_64-openbsd x86_64-linux-android riscv64-linux riscv64-linux-gnu s390x-linux ppc64le-linux
           universal-mingw x86_64-solaris sparc-solaris-2.11 loongarch64-linux powerpc64le-linux]
locals = %w[x86_64-linux aarch64-linux x86_64-linux-musl aarch64-linux-musl arm64-darwin23 arm64-darwin24
            x86_64-darwin22 x86_64-darwin23 armv7l-linux-eabihf x86_64-freebsd14 riscv64-linux]
out = {}
locals.each do |l|
  lp = Gem::Platform.new(l)
  out[l] = { "parsed" => [lp.cpu, lp.os, lp.version], "matches" => specs.select { |s| s == "ruby" || (Gem::Platform.new(s) === lp) } }
end
out["_rubygems"] = Gem::VERSION
puts JSON.pretty_generate(out)
