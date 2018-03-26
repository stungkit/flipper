require "json"
require "flipper/instrumenters/noop"
require "flipper/retry_strategy"

module Flipper
  module Cloud
    # Internal: Do not use this directly outside of this gem.
    class Request
      class ResponseError < StandardError
        def self.retry?(status)
          (500..599).cover?(status)
        end

        attr_reader :status

        def initialize(status)
          @status = status
          super("Request resulted in response with #{status} http status")
        end
      end

      def initialize(options = {})
        @client = options.fetch(:client)
        @limit = options.fetch(:limit, 1_000)
        @retry_strategy = options.fetch(:retry_strategy) { RetryStrategy.new }
        @instrumenter = options.fetch(:instrumenter, Instrumenters::Noop)
        reset
      end

      def <<(event)
        @events << event
        perform if @events.size >= @limit
        nil
      end

      def perform
        return if @events.empty?

        body = JSON.generate(events: @events.map(&:as_json))

        @retry_strategy.call do
          response = @client.post("/events", body: body)
          status = response.code.to_i
          raise ResponseError, status if ResponseError.retry?(status)
        end

        nil
      rescue => exception
        payload = {
          exception: exception,
          context: "Flipper::Cloud::Request#perform",
        }
        @instrumenter.instrument("exception.flipper", payload)
      ensure
        reset
      end

      private

      def reset
        @events = []
      end
    end
  end
end
