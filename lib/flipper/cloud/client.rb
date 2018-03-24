require "delegate"
require "flipper/event"
require "flipper/retry_strategy"
require "flipper/cloud/producer"
require "flipper/cloud/instrumenter"

module Flipper
  module Cloud
    # Internal: Do not use this directly outside of this gem.
    class Client < SimpleDelegator
      attr_reader :configuration
      attr_reader :flipper
      attr_reader :producer

      def initialize(options = {})
        @configuration = options.fetch(:configuration)
        @producer = build_producer
        @flipper = build_flipper
        super @flipper
      end

      private

      def build_flipper
        instrumenter_options = {
          instrumenter: @configuration.instrumenter,
          producer: @producer,
        }
        instrumenter = Cloud::Instrumenter.new(instrumenter_options)
        Flipper.new(@configuration.adapter, instrumenter: instrumenter)
      end

      def build_producer
        default_producer_options = {
          client: @configuration.client,
          instrumenter: @configuration.instrumenter,
          retry_strategy: RetryStrategy.new,
        }
        provided_producer_options = @configuration.producer_options
        producer_options = default_producer_options.merge(provided_producer_options)
        Producer.new(producer_options)
      end
    end
  end
end
