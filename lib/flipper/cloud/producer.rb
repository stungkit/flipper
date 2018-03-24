require "json"
require "thread"
require "flipper/instrumenters/noop"
require "flipper/retry_strategy"

module Flipper
  module Cloud
    class Producer
      attr_reader :client
      attr_reader :queue
      attr_reader :capacity
      attr_reader :batch_size
      attr_reader :flush_interval
      attr_reader :shutdown_timeout
      attr_reader :retry_strategy
      attr_reader :instrumenter

      def initialize(options = {})
        @client = options.fetch(:client)
        @queue = options.fetch(:queue) { Queue.new }
        @capacity = options.fetch(:capacity, 10_000)
        @batch_size = options.fetch(:batch_size, 1_000)
        @flush_interval = options.fetch(:flush_interval, 10)
        @shutdown_timeout = options.fetch(:shutdown_timeout, 5)
        @instrumenter = options.fetch(:instrumenter, Instrumenters::Noop)
        @retry_strategy = options.fetch(:retry_strategy) { RetryStrategy.new }

        if @flush_interval <= 0
          raise ArgumentError, "flush_interval must be greater than zero"
        end

        @worker_mutex = Mutex.new
        @timer_mutex = Mutex.new
        update_pid
      end

      def produce(event)
        ensure_threads_alive

        # TODO: Log statistics about dropped events and send to cloud?
        if @queue.size < @capacity
          @queue << [:produce, event]
        end

        nil
      end

      def shutdown
        @timer_thread.exit if @timer_thread
        @queue << [:shutdown, nil]

        if @worker_thread
          begin
            @worker_thread.join @shutdown_timeout
          rescue => exception
            instrument_exception exception
          end
        end

        nil
      end

      private

      def ensure_threads_alive
        ensure_worker_running
        ensure_timer_running
      end

      def ensure_worker_running
        # If another thread is starting worker thread, then return early so this
        # thread can enqueue and move on with life.
        return unless @worker_mutex.try_lock

        begin
          return if worker_running?

          update_pid
          @worker_thread = Thread.new do
            events = []

            loop do
              operation, item = @queue.pop

              case operation
              when :shutdown
                submit events
                events.clear
                break
              when :produce
                events << item
              when :deliver
                submit events
                events.clear
              else
                raise "unknown operation: #{operation}"
              end
            end
          end
        ensure
          @worker_mutex.unlock
        end
      end

      def worker_running?
        @worker_thread && @pid == Process.pid && @worker_thread.alive?
      end

      def ensure_timer_running
        # If another thread is starting timer thread, then return early so this
        # thread can enqueue and move on with life.
        return unless @timer_mutex.try_lock

        begin
          return if timer_running?

          update_pid
          @timer_thread = Thread.new do
            loop do
              sleep @flush_interval

              # TODO: don't do a deliver if a deliver happened for some other
              # reason recently
              @queue << [:deliver, nil]
            end
          end
        ensure
          @timer_mutex.unlock
        end
      end

      def timer_running?
        @timer_thread && @pid == Process.pid && @timer_thread.alive?
      end

      def submit(events)
        events.compact!
        return if events.empty?

        events.each_slice(@batch_size) do |slice|
          body = JSON.generate(events: slice.map(&:as_json))
          post body
        end

        nil
      rescue => exception
        instrument_exception(exception)
      end

      class SubmissionError < StandardError
        def self.retry?(status)
          (500..599).cover?(status)
        end

        attr_reader :status

        def initialize(status)
          @status = status
          super("Submission resulted in #{status} http status")
        end
      end

      def post(body)
        @retry_strategy.call do
          response = @client.post("/events", body: body)
          status = response.code.to_i

          if status != 201
            instrument_response_error(response)
            raise SubmissionError, status if SubmissionError.retry?(status)
          end
        end
      end

      def instrument_response_error(response)
        @instrumenter.instrument("producer_response_error.flipper", response: response)
      end

      def instrument_exception(exception)
        @instrumenter.instrument("producer_exception.flipper", exception: exception)
      end

      def update_pid
        @pid = Process.pid
      end
    end
  end
end
