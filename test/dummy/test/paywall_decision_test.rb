# frozen_string_literal: true

require "test_helper"

class PaywallDecisionTest < ActiveSupport::TestCase
  test "state sends the visible writing and marks a javascript wall" do
    page = page_with(
      title: "Just a moment...",
      text: "Enable JavaScript and cookies to continue",
      status: 403,
      challenge: RecordingStudio::WebReader::Challenge.new(
        kind: :javascript,
        evidence: [ RecordingStudio::WebReader::Evidence.new(source: :http, path: "status", value: 403) ]
      )
    )

    state = PaywallDecision.state_for(page)

    assert_includes state, "Status: 403"
    assert_includes state, "Challenge: javascript"
    assert_includes state, "Enable JavaScript and cookies to continue"
    refute_includes state, "cut to fit"
  end

  test "state says when the visible text was cut to fit" do
    page = page_with(title: "Long story", text: "word " * 4_000, status: 200, challenge: nil)

    state = PaywallDecision.state_for(page)

    assert_includes state, "The visible text was cut to fit. The cut is not a paywall."
    assert_operator state.length, :<=, PaywallDecision::TEXT_LIMIT + 400
  end

  private

  def page_with(title:, text:, status:, challenge:)
    RecordingStudio::WebReader::Page.new(
      url: "https://example.com/story",
      final_url: "https://example.com/story",
      status: status,
      headers: {},
      content_type: "text/html",
      title: title,
      description: nil,
      canonical_url: nil,
      text: text,
      html: "<html></html>",
      metadata: RecordingStudio::WebReader::Page::Metadata.new(
        open_graph: {}, twitter: {}, json_ld: [], article: {}, meta: {}
      ),
      links: [],
      images: [],
      challenge: challenge
    )
  end
end
