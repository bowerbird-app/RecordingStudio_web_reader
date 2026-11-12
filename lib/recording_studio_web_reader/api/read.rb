# frozen_string_literal: true

module RecordingStudio
  module WebReader
    module Api
      class Read
        INPUT_ERRORS = [
          InvalidUrlError,
          UnsafeUrlError,
          RegistryError,
          UnsupportedContentTypeError
        ].freeze

        def self.call(context)
          grant = context.access_grant
          grant.authorize!(recording: context.root_recording, role: VIEW_ROLE)

          page = RecordingStudio::WebReader.read(url(context.params))
          page.to_h
        rescue *INPUT_ERRORS => e
          raise RecordingStudioApi::InvalidActionInputError, e.message
        end

        def self.url(params)
          params[:url].to_s
        end

        private_class_method :url
      end
    end
  end
end
