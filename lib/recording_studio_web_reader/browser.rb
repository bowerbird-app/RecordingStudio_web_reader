# frozen_string_literal: true

require "fileutils"
require "uri"

require_relative "browser/chrome_process"
require_relative "browser/devtools"
require_relative "browser/session"

module RecordingStudio
  module WebReader
    # Opens one approved hop in Chrome. HTTP redirects are returned to the reader.
    class Browser
      REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze
      Decision = Data.define(:action, :error, :exchange)

      def self.call(hop)
        new(hop).call
      end

      def self.binary_path
        binary_candidates.find { |path| File.executable?(path.to_s) }
      end

      def self.decision_for(params, redirect_captured:, network_redirect: nil, hop_url: nil)
        return Decision.new(action: :fail, error: nil, exchange: nil) if redirect_captured
        return response_decision(params) if response_pause?(params)
        return follow_decision(params, network_redirect) if redirected_document?(params)

        request_decision(params, hop_url)
      end

      def self.header_map(headers)
        header_pairs(headers).each_with_object({}) do |(name, value), result|
          next if name.nil?

          result[name.to_s.downcase] = value.to_s
        end
      end

      def initialize(hop)
        @hop = hop
      end

      def call
        status, headers, body, content_type, location = Session.new(@hop).render
        {
          status: status,
          headers: headers,
          body: limit_body(body),
          content_type: content_type,
          location: location,
          address: @hop.fetch(:address)
        }
      end

      class << self
        private

        def binary_candidates
          [
            WebReader.configuration.chrome_path,
            ENV.fetch("GOOGLE_CHROME_BIN", nil),
            "/usr/bin/google-chrome",
            "/usr/bin/google-chrome-stable",
            "/usr/local/bin/google-chrome",
            "/usr/bin/chromium",
            "/usr/bin/chromium-browser"
          ].compact.reject { |path| path.to_s.strip.empty? }
        end

        def response_pause?(params)
          params.key?("responseStatusCode") || params["responseErrorReason"]
        end

        def redirected_document?(params)
          params["redirectedRequestId"] && params["resourceType"] == "Document"
        end

        def response_decision(params)
          if params["responseErrorReason"]
            error = params["resourceType"] == "Document" ? FetchError.new("The page could not be fetched") : nil
            return Decision.new(action: :block, error: error, exchange: nil)
          end

          status = params["responseStatusCode"].to_i
          headers = header_map(params["responseHeaders"])
          if REDIRECT_STATUSES.include?(status)
            return Decision.new(action: :redirect, error: nil, exchange: redirect_exchange(status, headers))
          end

          Decision.new(action: :continue_response, error: nil, exchange: { status: status, headers: headers })
        end

        def follow_decision(params, network_redirect)
          headers = network_redirect ? network_redirect[:headers] : {}
          status = network_redirect ? network_redirect[:status].to_i : 0
          status = 302 unless REDIRECT_STATUSES.include?(status)
          Decision.new(
            action: :redirect,
            error: nil,
            exchange: redirect_exchange(status, headers, params.dig("request", "url"))
          )
        end

        def redirect_exchange(status, headers, location = nil)
          target = location.to_s.strip
          target = headers["location"].to_s if target.empty?
          { status: status, headers: headers.merge("location" => target), location: target }
        end

        def request_decision(params, hop_url)
          url = params.dig("request", "url").to_s
          return continue_decision if same_hop?(url, hop_url)

          block = request_block(url)
          return continue_decision if block.nil?

          Decision.new(action: :block, error: document_error(params, block), exchange: nil)
        end

        def continue_decision
          Decision.new(action: :continue, error: nil, exchange: nil)
        end

        def same_hop?(url, hop_url)
          left = normalize_hop(url)
          right = normalize_hop(hop_url)
          return false if left.nil? || right.nil?

          left == right
        rescue URI::InvalidURIError
          false
        end

        def normalize_hop(value)
          uri = URI.parse(value.to_s)
          return unless uri.is_a?(URI::HTTP)

          uri.fragment = nil
          uri.user = nil
          uri.password = nil
          uri.normalize.to_s
        end

        def document_error(params, block)
          return unless params["resourceType"] == "Document" && block == :unsafe

          UnsafeUrlError.new("The URL is not allowed")
        end

        def request_block(url)
          return if url == "about:blank" || url.start_with?("data:", "blob:")

          Safety.resolve!(url)
          nil
        rescue UnsafeUrlError
          :unsafe
        rescue InvalidUrlError, FetchError
          :rejected
        end

        def header_pairs(headers)
          return headers.to_a if headers.is_a?(Hash)

          Array(headers).map { |header| header.is_a?(Hash) ? [header["name"], header["value"]] : header }
        end
      end

      private

      def limit_body(body)
        max_bytes = @hop.fetch(:max_bytes)
        return body if body.bytesize <= max_bytes
        return body.byteslice(0, max_bytes) if @hop[:on_overflow] == :truncate

        raise ResponseTooLargeError, "The response was too large"
      end
    end
  end
end
