require "socket"
require "thread"
require "flipper/adapters/memory"
require "flipper/instrumenters/memory"
require "flipper/api"
require "flipper"
require "rack/handler/webrick"

class TestServer
  attr_reader :port

  class RequestTrackingMiddleware
    def initialize(app, on_request)
      @app = app
      @on_request = on_request
    end

    def call(env)
      request = Rack::Request.new(env)
      @on_request.call request
      @app.call env
    end
  end

  attr_reader :requests

  def initialize
    @started = false
    @requests = []
    @log = StringIO.new
    @access_log = StringIO.new
    @thread = Thread.new { server.start }
    Timeout.timeout(10) { :wait until @started }
  end

  def log
    @log.string
  end

  def log_lines
    log.split("\n")
  end

  def access_log
    @access_log.string
  end

  def access_lines
    access_log.split("\n")
  end

  def reset
    adapter_source.clear
    @requests.clear
    @access_log.truncate(0)
    @log.truncate(0)
  end

  def shutdown
    @thread.kill if @thread
  end

  private

  def app
    @app ||= Flipper::Api.app(flipper) do |builder|
      on_request = ->(request) { @requests << request }
      builder.use RequestTrackingMiddleware, on_request
    end
  end

  def instrumenter
    @instrumenter ||= Flipper::Instrumenters::Memory.new
  end

  def flipper
    @flipper ||= Flipper.new(adapter, instrumenter: instrumenter)
  end

  def adapter
    @adapter ||= Flipper::Adapters::Memory.new(adapter_source)
  end

  def server
    @server ||= begin
      @port ||= 10_001
      server_options = {
        Port: @port,
        StartCallback: -> { @started = true },
        Logger: WEBrick::Log.new(@log, WEBrick::Log::INFO),
        AccessLog: [[@access_log, WEBrick::AccessLog::COMBINED_LOG_FORMAT]],
      }
      server = begin
        WEBrick::HTTPServer.new(server_options)
      rescue Errno::EADDRINUSE
        p "#{@port} in use, trying next with #{@port + 1}"
        @port += 1
        server_options[:Port] = @port
        retry
      end
      server.mount '/', Rack::Handler::WEBrick, app
      server
    end
  end

  def adapter_source
    @adapter_source ||= {}
  end
end
