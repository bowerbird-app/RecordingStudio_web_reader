# frozen_string_literal: true

RecordingStudioAI.configure do |config|
  config.typesafe_api_key = ENV["TYPESAFE_API_KEY"].presence || ENV["typesafe"].presence
  config.authorization_handler = RecordingStudioAI::AccessibleAuthorization.method(:call)
end
