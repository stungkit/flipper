require "thread"
require "flipper/instrumenters/noop"
require "flipper/retry_strategy"
require "flipper/cloud/request"

module Flipper
  module Cloud
    # Internal: Do not use this directly outside of this gem.
    class Producer
      # TODO: client, batch size and retry strategy feel like they should be packed up
      # together in a submitter/reporter object
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
            @instrumenter.instrument("exception.flipper", exception: exception)
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

      def worker_running?
        thread_healthy? @worker_thread
      end

      def timer_running?
        thread_healthy? @timer_thread
      end

      def thread_healthy?(thread)
        thread && pid_matches? && thread.alive?
      end

      # Does the initialized pid match the current pid. If not, then we have
      # forked or something and should likely re-create threads.
      def pid_matches?
        @pid == Process.pid
      end

      def update_pid
        @pid = Process.pid
      end
    end
  end
end
