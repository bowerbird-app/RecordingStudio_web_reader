# frozen_string_literal: true

require "active_support/notifications"
require "uri"

module RecordingStudio
  module WebReader
    class Read
      EVENT_NAME = "read.recording_studio_web_reader"
      PROBE_EVENT_NAME = "probe_image.recording_studio_web_reader"
      PROBE_BYTES = 65_536
      REDIRECTS = [301, 302, 303, 307, 308].freeze

      def self.call(url, strategy:)
        new(url, strategy:, operation: :read).call
      end

      def self.probe_image(url)
        new(url, strategy: :http, operation: :probe_image).probe_image
      end

      def initialize(url, strategy:, operation:)
        @url = url.to_s
        @strategy = strategy.to_sym
        @operation = operation
        @request_count = 0
        @bytes = 0
        @redirect_count = 0
        @status = nil
        @content_type = nil
        @host = host_label(@url)
      end

      def call
        return perform_and_record unless configuration.instrumentation_enabled

        instrumented(EVENT_NAME)
      end

      def probe_image
        return probe_and_record unless configuration.instrumentation_enabled

        instrumented(PROBE_EVENT_NAME) { probe }
      end

      private

      def instrumented(event_name)
        payload = base_payload
        started = monotonic_now
        error = nil
        result = ActiveSupport::Notifications.instrument(event_name, payload) do
          value = block_given? ? yield : capture(payload)
          fill_success(payload) unless payload[:success]
          value
        rescue Error => e
          error = fill_failure(payload, e)
        end
        payload[:duration_ms] = ((monotonic_now - started) * 1000).round
        error ? raise(error) : result
      end

      def perform_and_record
        payload = base_payload
        capture(payload)
      rescue Error => e
        fill_failure(payload, e)
        raise
      end

      def probe_and_record
        probe
      end

      def capture(payload)
        page = perform
        fill_success(payload, page)
        page
      end

      def perform
        destination = follow(
          Safety.resolve!(@url),
          max_bytes: configuration.max_response_bytes,
          on_overflow: :raise
        )
        raise UnsupportedContentTypeError.new(status: @status) unless Document.html?(@content_type, @body)

        Document.interpret(
          {
            status: @status,
            headers: @headers,
            body: @body,
            content_type: @content_type
          },
          url: @url,
          final_url: destination.url
        )
      end

      def probe
        destination = follow(
          Safety.resolve!(@url),
          max_bytes: PROBE_BYTES,
          on_overflow: :truncate,
          range: "bytes=0-#{PROBE_BYTES - 1}"
        )
        width, height = ImageHeader.dimensions(@body)
        {
          url: destination.url,
          width: width,
          height: height,
          aspect_ratio: Document.aspect_ratio(width, height),
          dimension_source: width && height ? :image_probe : nil
        }
      end

      def follow(destination, max_bytes:, on_overflow:, range: nil)
        @host = destination.host
        fetcher = registry.fetch_fetcher(@strategy)
        exchange = nil
        loop do
          exchange = fetcher.call(hop_for(destination, max_bytes:, on_overflow:, range:))
          remember(exchange)
          break unless redirect?(exchange)

          if @redirect_count >= configuration.max_redirects
            raise TooManyRedirectsError,
                  "The page redirected too many times"
          end

          location = exchange[:location]
          raise FetchError, "The page could not be fetched" if location.to_s.strip.empty?

          @redirect_count += 1
          destination = Safety.resolve!(next_url(destination.url, location))
        end
        destination
      end

      def hop_for(destination, max_bytes:, on_overflow:, range: nil)
        {
          url: destination.url,
          address: destination.address,
          host: destination.host,
          port: destination.port,
          https: destination.https,
          timeouts: {
            open: configuration.open_timeout,
            read: configuration.read_timeout,
            write: configuration.write_timeout
          },
          max_bytes: max_bytes,
          user_agent: configuration.user_agent,
          on_overflow: on_overflow,
          range: range
        }
      end

      def remember(exchange)
        @request_count += 1
        @bytes += exchange[:body].to_s.bytesize
        @status = exchange[:status]
        @headers = exchange[:headers]
        @body = exchange[:body]
        @content_type = exchange[:content_type]
      end

      def redirect?(exchange)
        REDIRECTS.include?(exchange[:status])
      end

      def next_url(current, location)
        URI.join(current, location.strip).to_s
      rescue URI::InvalidURIError
        raise FetchError, "The page could not be fetched"
      end

      def fill_success(payload, page = nil)
        payload[:success] = true
        payload[:host] = @host
        payload[:status] = @status
        payload[:content_type] = page ? page.content_type : Document.media_type(@content_type)
        payload[:content_type] = nil if payload[:content_type].to_s.empty?
        payload[:redirect_count] = @redirect_count
        payload[:bytes] = @bytes
        payload[:request_count] = @request_count
        payload[:error_type] = nil
        payload[:strategy] = @strategy
      end

      def fill_failure(payload, error)
        payload[:success] = false
        payload[:host] = @host
        payload[:status] = @status
        payload[:content_type] = Document.media_type(@content_type)
        payload[:content_type] = nil if payload[:content_type] == ""
        payload[:redirect_count] = @redirect_count
        payload[:bytes] = @bytes
        payload[:request_count] = @request_count
        payload[:error_type] = error.class.name
        payload[:strategy] = @strategy
        error
      end

      def base_payload
        {
          schema_version: 1,
          operation: @operation,
          strategy: @strategy,
          host: @host,
          success: false,
          status: nil,
          content_type: nil,
          redirect_count: 0,
          bytes: 0,
          request_count: 0,
          error_type: nil,
          cached: false
        }
      end

      def host_label(url)
        URI.parse(url.to_s).host&.downcase
      rescue URI::InvalidURIError
        nil
      end

      def configuration
        WebReader.configuration
      end

      def registry
        WebReader.send(:registry)
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
