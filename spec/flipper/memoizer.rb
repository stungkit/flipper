module Flipper
  class Memoizer
    attr_reader :adapter

    def initialize(adapter, &on_reset)
      @adapter = Adapters::Memoizable.new(adapter)
      @on_reset = on_reset
    end

    def call(&block)
      block.call self
    ensure
      reset unless @reset_later
    end

    def reset
      @on_reset.call
    end

    def reset_later
      @reset_later = true
      @on_reset
    end
  end
end
