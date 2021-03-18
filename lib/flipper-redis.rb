require 'flipper/adapters/redis'

Flipper.configure do |config|
  config.storage do
    client = Redis.new(url: ENV["FLIPPER_REDIS_URL"] || ENV["REDIS_URL"])
    Flipper::Adapters::Redis.new(client)
  end
end
