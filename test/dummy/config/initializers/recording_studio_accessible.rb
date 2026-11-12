# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  actors = [ "User" ]
  actors << "RecordingStudioApi::ApiClient" if defined?(RecordingStudioApi)
  config.access_actor_types = actors
end
