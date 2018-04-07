require "delegate"
require "flipper/retry_strategy"
require "flipper/cloud/reporter"
require "flipper/cloud/instrumenter"

module Flipper
  module Cloud
    # Internal: Do not use this directly outside of this gem.
    class Client < SimpleDelegator
      attr_reader :configuration
      attr_reader :flipper
      attr_reader :reporter

      def initialize(options = {})
        @configuration = options.fetch(:configuration)
        @reporter = build_reporter
        @flipper = build_flipper
        super @flipper
      end

      private

      def build_flipper
        instrumenter_options = {
          instrumenter: @configuration.instrumenter,
          reporter: @reporter,
        }
        instrumenter = Cloud::Instrumenter.new(instrumenter_options)
        Flipper.new(@configuration.adapter, instrumenter: instrumenter)
      end

      def build_reporter
        default_reporter_options = {
          client: @configuration.client,
          instrumenter: @configuration.instrumenter,
          retry_strategy: RetryStrategy.new,
        }
        provided_reporter_options = @configuration.reporter_options
        reporter_options = default_reporter_options.merge(provided_reporter_options)
        Reporter.new(reporter_options)
      end
    end
  end
end
