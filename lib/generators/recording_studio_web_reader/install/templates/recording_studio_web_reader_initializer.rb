# frozen_string_literal: true

RecordingStudio::WebReader.configure do |config|
  config.user_agent = "RecordingStudioWebReader/#{RecordingStudio::WebReader::VERSION}"
  # config.chrome_path = "/usr/bin/google-chrome"
  # Defaults to RecordingStudio::DEFAULT_LAYOUT. Pass a layout name, false,
  # or a callable that accepts controller:.
  # config.layout = RecordingStudio::DEFAULT_LAYOUT
end
