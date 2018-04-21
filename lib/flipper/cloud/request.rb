require "json"
require "securerandom"
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

      # Internal: The maximum number of items to buffer prior to performing
      # a request.
      attr_reader :limit

      # Internal: The array of events currently buffered.
      attr_reader :events

      def initialize(options = {})
        @client = options.fetch(:client)
        @limit = options.fetch(:limit, 1_000)
        @retry_strategy = options.fetch(:retry_strategy) { RetryStrategy.new }
        @instrumenter = options.fetch(:instrumenter, Instrumenters::Noop)
        @events = []
      end

      # Public: Adds event to Array of events. Performs request if number of
      # events is greater than or equal to limit.
      #
      # Returns Array of events to be consistent with Array#<<.
      def <<(event)
        @events << event
        perform if full?
        @events
      end

      def perform
        return if empty?

        # Stable request id across retries so we can at least try to detect
        # duplicates on the server side.
        headers = {
          "FLIPPER_REQUEST_ID" => SecureRandom.hex(16),
        }
        body = JSON.generate(events: @events.map(&:as_json))

        @retry_strategy.call do
          response = @client.post("/events", body: body, headers: headers)
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

      def full?
        @events.size >= @limit
      end

      def empty?
        @events.empty?
      end

      def reset
        @events.clear
      end
    end
  end
end
