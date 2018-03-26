require "delegate"
require "flipper/event"
require "flipper/feature"
require "flipper/instrumenters/noop"

module Flipper
  module Cloud
    # Internal: Do not use this directly outside of this gem.
    class Instrumenter < SimpleDelegator
      attr_reader :producer
      attr_reader :instrumenter

      def initialize(options = {})
        @producer = options.fetch(:producer)
        @instrumenter = options.fetch(:instrumenter, Instrumenters::Noop)
        super @instrumenter
      end

      def instrument(name, payload = {}, &block)
        result = @instrumenter.instrument(name, payload, &block)

        begin
          produce name, payload
        rescue => exception
          payload = {
            exception: exception,
            context: "Flipper::Cloud::Instrumenter#instrument",
          }
          @instrumenter.instrument("exception.flipper", payload)
        end

        result
      end

      private

      def produce(name, payload)
        return unless name == Flipper::Feature::InstrumentationName
        return unless :enabled? == payload[:operation]

        dimensions = {
          "feature" => payload[:feature_name].to_s,
          "result" => payload[:result].to_s,
        }
        thing = payload[:thing]
        dimensions["flipper_id"] = thing.value if thing

        attributes = {
          type: "enabled",
          dimensions: dimensions,
        }
        event = Flipper::Event.new(attributes)
        @producer.produce event
      end
    end
  end
end
