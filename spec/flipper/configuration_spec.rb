require 'helper'
require 'flipper/configuration'

RSpec.describe Flipper::Configuration do
  describe '#default' do
    it 'returns instance using Memory adapter' do
      expect(subject.default).to be_a(Flipper::DSL)
      # All adapter are wrapped in Memoizable
      expect(subject.default.adapter.adapter).to be_a(Flipper::Adapters::Memory)
    end

    it 'can be set default' do
      instance = Flipper.new(Flipper::Adapters::Memory.new)
      expect(subject.default).not_to be(instance)
      subject.default { instance }
      expect(subject.default).to be(instance)
    end
  end

  describe '#storage' do
    it 'sets the storage adapter with a block' do
      instance = Flipper::Adapters::Memory.new
      subject.storage { instance }
      expect(subject.default).to be_a(Flipper::DSL)
      # All adapter are wrapped in Memoizable
      expect(subject.default.adapter.adapter).to be(instance)
    end

    it 'sets the storage adapter with class name' do
      require "flipper/adapters/active_record"
      subject.storage Flipper::Adapters::ActiveRecord
      # Adapters are wrapped in Memoizable by default
      expect(subject.adapter.adapter).to be_a(Flipper::Adapters::ActiveRecord)
    end
  end

  describe '#use' do
    it 'wraps storage adapter' do
      require "flipper/adapters/redis_cache"
      client = double("redis client")
      subject.use Flipper::Adapters::RedisCache, client
      expect(subject.adapter).to be_a(Flipper::Adapters::RedisCache)
    end
  end
end
