require 'flipper/adapters/sequel'

Flipper.configure do |config|
  config.storage do
    Flipper::Adapters::Sequel.new
  end
end
