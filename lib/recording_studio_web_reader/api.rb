# frozen_string_literal: true

require_relative "api/read"

module RecordingStudio
  module WebReader
    # Registers one public GET endpoint when Recording Studio API is loaded.
    # MCP advertises registered endpoints automatically. This gem adds no MCP tools.
    module Api
      NAME = "web_reader.read"
      PATH = "web_reader/read"
      VIEW_ROLE = :view

      OPENAPI = {
        title: "Web Reader - Read",
        summary: "Visit one public page and return what is there",
        description: "Visit one public http or https URL and return the normalized page. " \
                     "The same safety checks as RecordingStudio::WebReader.read apply. " \
                     "Private, metadata, and userinfo URLs are refused. " \
                     "The host's configured fetch strategy is always used. " \
                     "This endpoint has no strategy query parameter.",
        tags: ["Web Reader"],
        parameters: [
          {
            name: "url",
            in: "query",
            required: true,
            description: "Absolute http or https URL to visit.",
            schema: { type: "string" }
          }
        ]
      }.freeze

      INPUT_CONTRACT = {
        reject_unknown: false,
        fields: {
          url: {
            type: :string,
            required: true,
            description: "Absolute http or https URL to visit."
          }
        }
      }.freeze

      class << self
        def register!
          return unless defined?(::RecordingStudioApi)

          registered = false
          RecordingStudioApi.configuration.each_api do |api|
            next if already_registered?(api: api.name)

            RecordingStudioApi.register_endpoint(
              NAME,
              api: api.name,
              http_verb: :get,
              path: PATH,
              handler: Read,
              openapi: OPENAPI,
              input_contract: INPUT_CONTRACT
            )
            registered = true
          end
          registered || nil
        end

        def already_registered?(api: :public)
          return false unless defined?(::RecordingStudioApi)

          RecordingStudioApi.registered_endpoint(NAME, api: api).present?
        end
      end
    end
  end
end
