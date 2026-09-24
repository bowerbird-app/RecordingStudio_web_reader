# frozen_string_literal: true

require Rails.root.join("lib/dummy_browser")
require Rails.root.join("lib/paywall_decision")

RecordingStudio::WebReader.configure do |config|
  config.user_agent = "RecordingStudioWebReaderDummy/#{RecordingStudio::WebReader::VERSION}"
end

RecordingStudio::WebReader.register_analysis(:paywall, PaywallDecision, override: true)
RecordingStudio::WebReader.register_fetcher(:browser, DummyBrowser, override: true)
