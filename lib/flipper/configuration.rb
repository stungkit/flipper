module Flipper
  class Configuration
    class Middleware
      attr_reader :klass, :args, :block

      def initialize(klass, *args, &block)
        @klass, @args, @block = klass, args, block
      end

      def build(adapter)
        @instance ||= klass.new(adapter, *args, &block)
      end
    end

    def initialize
      @storage = -> { Flipper::Adapters::Memory.new }
      @default = -> { Flipper.new(adapter) }
      @middleware = []

      use Adapters::Memoizable
    end

    def use(adapter, *args, &block)
      @middleware.push Middleware.new(adapter, *args, &block)
    end

    # Returns the default adapter used by flipper. The adapter is built by initializing
    # the default storage adapter, and wrapping it in any middleware
    #
    #   Flipper.configure do |config|
    #     config.use Flipper::Adapter::ReadOnly
    #     config.use Flipper::Adapter::RedisCache, Redis.new
    #     config.storage Flipper::Adapter::ActiveRecord
    #   end
    #
    def adapter
      @middleware.reduce(storage) do |adapter, middleware|
        middleware.build(adapter)
      end
    end

    # Controls the default instance for flipper. When used with a block it
    # assigns a new default block to use to generate an instance. When used
    # without a block, it performs a block invocation and returns the result.
    #
    #   configuration = Flipper::Configuration.new
    #   configuration.default # => Flipper::DSL instance using Memory adapter
    #
    #   # sets the default block to generate a new instance using ActiveRecord adapter
    #   configuration.default do
    #     require "flipper-active_record"
    #     Flipper.new(Flipper::Adapters::ActiveRecord.new)
    #   end
    #
    #   configuration.default # => Flipper::DSL instance using ActiveRecord adapter
    #
    # Returns result of default block invocation if called without block. If
    # called with block, assigns the default block.
    def default(&block)
      if block_given?
        @default = block
      else
        @default.call
      end
    end

    def storage(klass = nil, &block)
      if klass
        @storage = -> { klass.new }
      elsif block
        @storage = block
      else
        @storage.call
      end
    end
  end
end
