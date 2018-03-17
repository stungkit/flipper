require "delegate"
require "flipper/event"
require "flipper/util"
require "flipper/cloud/producer"
require "flipper/cloud/instrumenter"

module Flipper
  module Cloud
    class Client < SimpleDelegator
      attr_reader :configuration
      attr_reader :flipper
      attr_reader :producer

      def initialize(configuration:)
        @configuration = configuration
        @producer = build_producer
        @flipper = build_flipper
        super @flipper
      end

      private

      def build_flipper
        instrumenter_options = {
          instrumenter: configuration.instrumenter,
          producer: @producer,
        }
        instrumenter = Cloud::Instrumenter.new(instrumenter_options)
        Flipper.new(configuration.adapter, instrumenter: instrumenter)
      end

      def build_producer
        default_producer_options = {
          instrumenter: @configuration.instrumenter,
          client: @configuration.client,
        }
        provided_producer_options = @configuration.producer_options
        producer_options = default_producer_options.merge(provided_producer_options)
        Producer.new(producer_options)
      end
    end
  end
end
