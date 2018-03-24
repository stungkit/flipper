require "flipper/timestamp"
require "flipper/instrumenters/noop"

module Flipper
  module Cloud
    class Instrumenter
      attr_reader :producer
      attr_reader :instrumenter

      def initialize(options = {})
        @producer = options.fetch(:producer)
        @instrumenter = options.fetch(:instrumenter, Instrumenters::Noop)
      end

      def instrument(name, payload = {}, &block)
        result = @instrumenter.instrument(name, payload, &block)
        produce name, payload
        result
      end

      private

      def produce(name, payload)
        return unless name == Flipper::Feature::InstrumentationName
        return unless :enabled? == payload[:operation]

        attributes = {
          type: "enabled",
          dimensions: {
            "feature" => payload[:feature_name].to_s,
            "result" => payload[:result].to_s,
          },
          timestamp: Flipper::Timestamp.generate,
        }

        thing = payload[:thing]
        attributes[:dimensions]["flipper_id"] = thing.value if thing

        event = Flipper::Event.new(attributes)
        @producer.produce event
      rescue => exception
        @instrumenter.instrument("exception.flipper", exception: exception)
      end
    end
  end
end
