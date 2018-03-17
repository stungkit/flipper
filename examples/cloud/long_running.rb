require File.expand_path('../../example_setup', __FILE__)

require 'flipper/cloud'

token = ENV.fetch("TOKEN") { abort "TOKEN environment variable not set." }
feature_name = ENV.fetch("FEATURE") { "testing" }.to_sym

Flipper.configure do |config|
  config.default do
    Flipper::Cloud.new(token) do |cloud|
      cloud.url = "http://localhost:5000/adapter"
      cloud.debug_output = STDOUT
    end
  end
end

actor = Flipper::Actor.new("User;23")

loop do
  Flipper.enabled?(feature_name, actor)
  sleep 0.1
end
