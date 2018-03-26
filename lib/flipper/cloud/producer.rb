require "thread"
require "flipper/instrumenters/noop"
require "flipper/retry_strategy"
require "flipper/cloud/request"

module Flipper
  module Cloud
    # Internal: Do not use this directly outside of this gem.
    class Producer
      # Public: The Flipper::Adapters::Http::Client instance to use to make requests.
      attr_reader :client

      # Public: The queue that stores events until they can be eventually sent
      # to cloud.
      attr_reader :queue

      # Public: The Integer number of events to buffer in the queue. If the
      # queue reaches this size, any more events will be discarded.
      # Default is 10,000.
      attr_reader :capacity

      # Public: The Integer maximum number of events to send to cloud in a
      # single request. Once this many events have been batched up, a request
      # will be submitted even if the flush_interval has not been reached.
      # Default is 1,000.
      attr_reader :batch_size

      # Public: The Integer or Float number of seconds to wait and batch up
      # events. Once this interval is reached, the batch of events will be
      # submitted to cloud even if less than the batch_size.
      attr_reader :flush_interval

      # Public: The Integer or Float maximum number of seconds to wait when
      # attempting graceful shutdown of the producer.
      attr_reader :shutdown_timeout

      # Public: The retry strategy to use when there are errors making requests
      # to cloud. Default is new Flipper::RetryStrategy instance.
      attr_reader :retry_strategy

      # Public: The instrumenter to use. Default is Flipper::Instrumenters::Noop.
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
        update_worker_pid
        update_timer_pid
      end

      def produce(event)
        ensure_threads_alive

        if @queue.size < @capacity
          @queue << [:produce, event]
        else
          @instrumenter.instrument("event_discarded.flipper")
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
            payload = {
              exception: exception,
              context: "Flipper::Cloud::Producer#shutdown",
            }
            @instrumenter.instrument("exception.flipper", payload)
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

          update_worker_pid
          @worker_thread = Thread.new do
            request_options = {
              client: @client,
              limit: @batch_size,
              retry_strategy: @retry_strategy,
              instrumenter: @instrumenter,
            }
            request = Request.new(request_options)

            loop do
              operation, item = @queue.pop

              case operation
              when :shutdown
                request.perform
                break
              when :produce
                request << item
              when :deliver
                # TODO: don't do a deliver if a deliver happened for some other
                # reason recently like the request was full or a manual deliver
                # was called
                request.perform
              else
                raise "unknown operation: #{operation}"
              end
            end
          end
        ensure
          @worker_mutex.unlock
        end
      end

      def ensure_timer_running
        # If another thread is starting timer thread, then return early so this
        # thread can enqueue and move on with life.
        return unless @timer_mutex.try_lock

        begin
          return if timer_running?

          update_timer_pid
          @timer_thread = Thread.new do
            loop do
              sleep @flush_interval

              @queue << [:deliver, nil]
            end
          end
        ensure
          @timer_mutex.unlock
        end
      end

      # Is the worker thread assigned, alive and created in the same process that
      # we are currently in.
      def worker_running?
        @worker_thread && @worker_pid == Process.pid && @worker_thread.alive?
      end

      # Is the timer thread assigned, alive and created in the same process that
      # we are currently in.
      def timer_running?
        @timer_thread && @timer_pid == Process.pid && @timer_thread.alive?
      end

      # Update the pid of the process that started the timer thread.
      def update_timer_pid
        @timer_pid = Process.pid
      end

      # Update the pid of the process that started the worker thread.
      def update_worker_pid
        @worker_pid = Process.pid
      end
    end
  end
end
