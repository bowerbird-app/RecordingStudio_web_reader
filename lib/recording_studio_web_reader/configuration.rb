# frozen_string_literal: true

module RecordingStudio
  module WebReader
    class Configuration
      DEFAULT_OPEN_TIMEOUT = 5
      DEFAULT_READ_TIMEOUT = 10
      DEFAULT_WRITE_TIMEOUT = 5
      DEFAULT_MAX_REDIRECTS = 5
      DEFAULT_MAX_RESPONSE_BYTES = 2_000_000
      DEFAULT_STRATEGY = :http

      attr_writer :open_timeout, :read_timeout, :write_timeout,
                  :max_redirects, :max_response_bytes,
                  :instrumentation_enabled, :fetch_strategy
      attr_accessor :user_agent
      attr_reader :hooks

      def initialize
        @user_agent = "RecordingStudioWebReader/#{VERSION}"
        @open_timeout = DEFAULT_OPEN_TIMEOUT
        @read_timeout = DEFAULT_READ_TIMEOUT
        @write_timeout = DEFAULT_WRITE_TIMEOUT
        @max_redirects = DEFAULT_MAX_REDIRECTS
        @max_response_bytes = DEFAULT_MAX_RESPONSE_BYTES
        @instrumentation_enabled = true
        @fetch_strategy = DEFAULT_STRATEGY
        @hooks = RecordingStudio::Hooks.new
      end

      def open_timeout
        @open_timeout.nil? ? DEFAULT_OPEN_TIMEOUT : @open_timeout
      end

      def read_timeout
        @read_timeout.nil? ? DEFAULT_READ_TIMEOUT : @read_timeout
      end

      def write_timeout
        @write_timeout.nil? ? DEFAULT_WRITE_TIMEOUT : @write_timeout
      end

      def max_redirects
        @max_redirects.nil? ? DEFAULT_MAX_REDIRECTS : @max_redirects
      end

      def max_response_bytes
        @max_response_bytes.nil? ? DEFAULT_MAX_RESPONSE_BYTES : @max_response_bytes
      end

      def fetch_strategy
        value = @fetch_strategy.nil? ? DEFAULT_STRATEGY : @fetch_strategy
        value.respond_to?(:to_sym) ? value.to_sym : value
      end

      def instrumentation_enabled
        @instrumentation_enabled.nil? || @instrumentation_enabled
      end

      def to_h
        {
          user_agent: user_agent,
          open_timeout: open_timeout,
          read_timeout: read_timeout,
          write_timeout: write_timeout,
          max_redirects: max_redirects,
          max_response_bytes: max_response_bytes,
          fetch_strategy: fetch_strategy,
          instrumentation_enabled: instrumentation_enabled,
          hooks_registered: hooks.registered_counts
        }
      end

      def inspect
        "#<#{self.class.name} #{to_h.inspect}>"
      end

      def merge!(hash)
        return unless hash.respond_to?(:each)

        hash.each do |key, value|
          setter = "#{key}="
          public_send(setter, value) if respond_to?(setter)
        end
      end
    end
  end
end
