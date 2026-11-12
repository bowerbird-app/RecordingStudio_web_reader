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
        summary: "Web Reader - Read",
        description: "Visit one public http or https URL and return the normalized page. " \
                     "The same safety checks as RecordingStudio::WebReader.read apply. " \
                     "Private, metadata, and userinfo URLs are refused.",
        tags: ["Web Reader"],
        parameters: [
          {
            name: "url",
            in: "query",
            required: true,
            description: "Absolute http or https URL to visit.",
            schema: { type: "string" }
          },
          {
            name: "strategy",
            in: "query",
            required: false,
            description: "Registered fetch strategy. Omit to use the configured default.",
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
          },
          strategy: {
            type: :string,
            required: false,
            description: "Registered fetch strategy. Omit to use the configured default."
          }
        }
      }.freeze

      class << self
        def register!
          return unless available?

          registered = false
          each_api_name do |api_name|
            next if already_registered?(api: api_name)

            RecordingStudioApi.register_endpoint(
              NAME,
              api: api_name,
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

        def available?
          defined?(RecordingStudioApi) &&
            RecordingStudioApi.respond_to?(:register_endpoint) &&
            RecordingStudioApi.respond_to?(:registered_endpoint)
        end

        def already_registered?(api: :public)
          return false unless available?

          RecordingStudioApi.registered_endpoint(NAME, api: api).present?
        end

        def each_api_name
          return enum_for(:each_api_name) unless block_given?
          return yield(:public) unless RecordingStudioApi.respond_to?(:configuration)

          configuration = RecordingStudioApi.configuration
          unless configuration.respond_to?(:each_api)
            yield(:public)
            return
          end

          configuration.each_api do |api|
            yield api.respond_to?(:name) ? api.name : :public
          end
        end
      end
    end
  end
end
