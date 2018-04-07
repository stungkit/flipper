require 'flipper'
require 'minitest/autorun'
require 'minitest/unit'
require 'pathname'

Dir['./lib/flipper/test/*.rb'].each { |f| require(f) }

FlipperRoot = Pathname(__FILE__).dirname.join('..').expand_path
