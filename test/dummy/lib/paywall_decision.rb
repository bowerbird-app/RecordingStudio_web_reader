# frozen_string_literal: true

class PaywallDecision
  TEXT_LIMIT = 12_000

  QUESTIONS = {
    paywall: {
      type: :choice,
      instructions: "The page loaded in a browser or as a download. Decide whether a paywall holds back the writing. " \
                    "A JavaScript wall or an error is blocked, not a paywall. A note that the text was cut to fit is not a paywall.",
      criteria: {
        open: "The writing a reader came for is on the page.",
        partial: "Some of that writing is visible, then the page asks for payment to continue.",
        paywall: "The page loaded, and the writing is held back until someone pays or subscribes.",
        login: "The page asks for a sign-in before the writing.",
        blocked: "The response is an error or a JavaScript wall, so there is no article to judge.",
        unknown: "There is not enough text to tell."
      }
    }
  }.freeze

  LABELS = {
    open: "No paywall",
    partial: "Some of the writing is behind a paywall",
    paywall: "The page is up, and the writing is behind a paywall",
    login: "Sign in to read the writing",
    blocked: "This is not a paywall. The page did not load.",
    unknown: "Jev could not tell"
  }.freeze

  def self.call(page, root_recording:, initiator:)
    response = RecordingStudioAI.decide!(
      state: state_for(page),
      questions: QUESTIONS,
      purpose: "page_paywall",
      root_recording: root_recording,
      initiator: initiator
    )
    answer = response.answers[:paywall]
    choice = answer.choice.to_sym

    {
      value: choice,
      confidence: answer.confidence,
      reason: LABELS.fetch(choice),
      evidence: [
        { source: :http, path: "status", value: page.status },
        { source: :document, path: "title", value: page.title },
        { source: :document, path: "challenge", value: page.challenge&.kind&.to_s || "none" },
        { source: :text, path: "text.excerpt", value: page.text.to_s[0, 180] }
      ]
    }
  end

  def self.state_for(page)
    text = page.text.to_s
    excerpt = text[0, TEXT_LIMIT]
    lines = [
      "Status: #{page.status}",
      "Final URL: #{page.final_url}",
      "Title: #{page.title}",
      "Challenge: #{page.challenge&.kind || "none"}",
      "",
      "Visible text:",
      excerpt.presence || "(none)"
    ]
    lines << "" << "The visible text was cut to fit. The cut is not a paywall." if text.length > TEXT_LIMIT
    lines.join("\n")
  end

  def self.label(choice)
    LABELS.fetch(choice.to_sym)
  end
end
