require 'uri'
require 'openssl'
require 'flipper/version'
require 'flipper/timestamp'

module Flipper
  module Adapters
    class Http
      class Client
        DEFAULT_HEADERS = {
          'Content-Type' => 'application/json',
          'Accept' => 'application/json',
          'User-Agent' => "Flipper HTTP Adapter v#{VERSION}",
        }.freeze

        HTTPS_SCHEME = "https".freeze

        VALID_SCHEMES = [
          "http".freeze,
          "https".freeze,
        ].freeze

        def self.url_for(url, path)
          uri = URI(url)

          unless VALID_SCHEMES.include?(uri.scheme)
            raise ArgumentError, <<-ERR
              #{url} does not have valid scheme. schema was #{uri.scheme} \
              and valid schemes are #{VALID_SCHEMES.inspect}
            ERR
          end

          path_uri = URI(path)
          uri.path += "/#{path_uri.path}".squeeze("/".freeze)
          uri.path.squeeze!("/".freeze)

          if path_uri.query
            if uri.query
              uri.query += "&#{path_uri.query}"
            else
              uri.query = path_uri.query
            end

            uri.query.squeeze!("&".freeze)
          end

          uri.to_s
        end

        attr_reader :url
        attr_reader :headers
        attr_reader :basic_auth_username
        attr_reader :basic_auth_password
        attr_reader :read_timeout
        attr_reader :open_timeout
        attr_reader :debug_output

        def initialize(options = {})
          @url = options.fetch(:url)
          @headers = DEFAULT_HEADERS.merge(options[:headers] || {})
          @basic_auth_username = options[:basic_auth_username]
          @basic_auth_password = options[:basic_auth_password]
          @read_timeout = options[:read_timeout]
          @open_timeout = options[:open_timeout]
          @debug_output = options[:debug_output]
        end

        def get(path, headers: {})
          perform Net::HTTP::Get, path, @headers.merge(headers)
        end

        def post(path, body: nil, headers: {})
          perform Net::HTTP::Post, path, @headers.merge(headers), body: body
        end

        def delete(path, body: nil, headers: {})
          perform Net::HTTP::Delete, path, @headers.merge(headers), body: body
        end

        private

        def perform(http_method, path, headers = {}, options = {})
          url = self.class.url_for(@url, path)
          uri = URI(url)
          http = build_http(uri)
          request = build_request(http_method, uri, headers, options)
          http.request(request)
        end

        def build_http(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.read_timeout = @read_timeout if @read_timeout
          http.open_timeout = @open_timeout if @open_timeout
          http.set_debug_output(@debug_output) if @debug_output

          if uri.scheme == HTTPS_SCHEME
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          end

          http
        end

        def build_request(http_method, uri, headers, options)
          request_headers = {
            "FLIPPER_TIMESTAMP".freeze => Flipper::Timestamp.generate.to_s,
          }.merge(headers)
          request = http_method.new(uri.request_uri)
          request.initialize_http_header(request_headers)

          body = options[:body]
          request.body = body if body

          if @basic_auth_username && @basic_auth_password
            request.basic_auth(@basic_auth_username, @basic_auth_password)
          end

          request
        end
      end
    end
  end
end
