# frozen_string_literal: true

require Rails.root.join("lib/dummy_browser")

RecordingStudio::WebReader.configure do |config|
  config.user_agent = "RecordingStudioWebReaderDummy/#{RecordingStudio::WebReader::VERSION}"
end

module DummyPaywallAnalysis
  module_function

  def call(page)
    length = page.text.to_s.length
    {
      value: length < 400 ? :hard_paywall : :open,
      confidence: 1.0,
      reason: "Text length is an observation.",
      evidence: [
        { source: :text, path: "text.length", value: length },
        { source: :http, path: "status", value: page.status }
      ]
    }
  end
end

RecordingStudio::WebReader.register_analysis(:paywall, DummyPaywallAnalysis, override: true)
RecordingStudio::WebReader.register_fetcher(:browser, DummyBrowser, override: true)
