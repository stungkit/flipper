module Flipper
  # A utility class to manage the state of memoization
  class Memoizer
    def initialize(adapter)
      @adapter = Adapters::Memoizable.new(adapter)
      reset
    end

    # Public: Returns a memoizing adapter or the original adapter based on the
    # state of `memoizing?`
    def adapter
      memoizing? ? @adapter : @adapter.adapter
    end

    # Public: Boolean indicating if memoization is currently happening
    def memoizing?
      @memoizing
    end

    # Private: Call the block and reset when it completes
    def call(&block)
      @memoizing = true
      @reset_later = false

      block.call self
    ensure
      reset unless @reset_later
    end

    # Public: Reset the state of the memoizer and clear the cache
    def reset
      @memoizing = false
      @adapter.cache.clear
    end

    # Public: Prevent memoizer from resetting after calling block
    #
    # Returns a Proc that can be called later to perform the reset
    def reset_later
      @reset_later = true
      method(:reset)
    end
  end
end
