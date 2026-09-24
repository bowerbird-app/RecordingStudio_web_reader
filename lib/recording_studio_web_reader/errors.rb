# frozen_string_literal: true

module RecordingStudio
  module WebReader
    class Error < StandardError; end

    class InvalidUrlError < Error; end
    class UnsafeUrlError < Error; end
    class FetchError < Error; end
    class TimeoutError < FetchError; end
    class TooManyRedirectsError < Error; end
    class ResponseTooLargeError < Error; end

    class UnsupportedContentTypeError < Error
      attr_reader :status

      def initialize(message = "The content type is not supported", status: nil)
        @status = status
        super(message)
      end
    end

    class ConfigurationError < Error; end
    class RegistryError < Error; end
  end
end
