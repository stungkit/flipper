require "flipper/instrumenters/noop"

module Flipper
  class RetryStrategy
    attr_reader :limit
    attr_reader :sleep
    attr_reader :raise_at_limit
    attr_reader :base
    attr_reader :max_delay
    attr_reader :instrumenter

    # base - The starting delay between retries.
    # max_delay - The maximum to expand the delay between retries.
    def initialize(options = {})
      @limit = options.fetch(:limit, 10)
      @sleep = options.fetch(:sleep, true)
      @base = options.fetch(:base, 0.5)
      @max_delay = options.fetch(:max_delay, 2.0)
      @raise_at_limit = options.fetch(:raise_at_limit, false)
      @instrumenter = options.fetch(:instrumenter, Instrumenters::Noop)
    end

    def call
      raise ArgumentError, "block is required" unless block_given?

      attempts ||= 0

      begin
        attempts += 1
        yield
      rescue => exception
        payload = {
          context: "Flipper::RetryStrategy#call",
          exception: exception,
          attempts: attempts,
        }
        @instrumenter.instrument("exception.flipper", payload)

        if attempts >= @limit
          if @raise_at_limit
            raise
          else
            return
          end
        end
        ::Kernel.sleep sleep_for_attempts(attempts) if @sleep

        retry
      end
    end

    private

    # Private: Given the number of attempts, it returns the number of seconds
    # to sleep. Should always return a Float larger than base. Should always
    # return a Float not larger than @base + @max_delay.
    #
    # attempts - The number of attempts.
    #
    # Returns Float seconds to sleep.
    def sleep_for_attempts(attempts)
      sleep_seconds = [@base * (2**(attempts - 1)), @max_delay].min
      sleep_seconds *= (0.5 * (1 + rand))
      [@base, sleep_seconds].max
    end
  end
end
