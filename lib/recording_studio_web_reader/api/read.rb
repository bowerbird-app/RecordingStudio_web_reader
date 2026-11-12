# frozen_string_literal: true

module RecordingStudio
  module WebReader
    module Api
      class Read
        def self.call(context)
          grant = context.access_grant
          grant.authorize!(recording: context.root_recording, role: VIEW_ROLE)

          page = RecordingStudio::WebReader.read(url(context.params), **read_options(context.params))
          page.to_h
        rescue RecordingStudio::WebReader::InvalidUrlError, RecordingStudio::WebReader::UnsafeUrlError => e
          raise RecordingStudioApi::InvalidActionInputError, e.message
        end

        def self.url(params)
          params[:url].to_s
        end

        def self.read_options(params)
          strategy = params[:strategy]
          return {} if strategy.blank?

          { strategy: strategy }
        end

        private_class_method :url, :read_options
      end
    end
  end
end
