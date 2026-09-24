# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module RecordingStudio
  module WebReader
    class Http
      def self.call(hop)
        new(hop).call
      end

      def initialize(hop)
        @hop = hop
      end

      def call
        perform
      rescue RecordingStudio::WebReader::ResponseTooLargeError,
             RecordingStudio::WebReader::TimeoutError,
             RecordingStudio::WebReader::FetchError
        raise
      rescue ::Timeout::Error
        raise TimeoutError, "The request timed out"
      rescue SocketError, OpenSSL::SSL::SSLError, IOError, SystemCallError
        raise FetchError, "The page could not be fetched"
      end

      private

      def perform
        uri = URI(@hop.fetch(:url))
        http = Net::HTTP.new(@hop.fetch(:host), @hop.fetch(:port))
        http.ipaddr = @hop.fetch(:address)
        http.use_ssl = @hop.fetch(:https)
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER if @hop.fetch(:https)
        http.open_timeout = @hop.dig(:timeouts, :open)
        http.read_timeout = @hop.dig(:timeouts, :read)
        http.write_timeout = @hop.dig(:timeouts, :write)
        http.max_retries = 0 if http.respond_to?(:max_retries=)

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = @hop.fetch(:user_agent).to_s
        request["Accept"] = "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8"
        request["Range"] = @hop[:range] if @hop[:range]

        http.request(request) do |response|
          return read_response(response)
        end
      end

      def read_response(response)
        headers = {}
        response.each_header { |name, value| headers[name.downcase] = value }
        max_bytes = @hop.fetch(:max_bytes)
        declared = headers["content-length"].to_i
        if @hop[:on_overflow] != :truncate && declared > max_bytes
          raise ResponseTooLargeError, "The response was too large"
        end

        body = +""
        response.read_body do |chunk|
          body << chunk
          next if body.bytesize <= max_bytes

          if @hop[:on_overflow] == :truncate
            body = body.byteslice(0, max_bytes)
            break
          end

          raise ResponseTooLargeError, "The response was too large"
        end

        {
          status: response.code.to_i,
          headers: headers,
          body: body,
          content_type: headers["content-type"],
          location: headers["location"],
          address: @hop.fetch(:address)
        }
      end
    end
  end
end
