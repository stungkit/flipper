module Flipper
  module Instrumenters
    # Instrumentor that is useful for tests as it stores each of the events that
    # are instrumented.
    class Memory
      Event = Struct.new(:name, :payload, :result)

      attr_reader :events

      def initialize
        reset
      end

      def instrument(name, payload = {})
        result = (yield payload if block_given?)
        @events << Event.new(name, payload, result)
        result
      end

      def events_by_name(name)
        @events.select { |event| event.name == name }
      end

      def event_by_name(name)
        events_by_name(name).first
      end

      def reset
        @events = []
      end
    end
  end
end
