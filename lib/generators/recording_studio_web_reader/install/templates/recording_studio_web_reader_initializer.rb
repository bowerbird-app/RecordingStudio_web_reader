# frozen_string_literal: true

RecordingStudio::WebReader.configure do |config|
  config.user_agent = "RecordingStudioWebReader/#{RecordingStudio::WebReader::VERSION}"
  # config.chrome_path = "/usr/bin/google-chrome"
end
