# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    @url = params[:url].to_s
    @probe = params[:probe] == "1"
    @approach = params[:approach] == "browser" ? "browser" : "download"
    return if @url.blank?

    @page = RecordingStudio::WebReader.read(@url, strategy: @approach == "browser" ? :browser : :http)
    @page = RecordingStudio::WebReader.probe_images(@page) if @probe
    ask_paywall(@page)
  rescue RecordingStudio::WebReader::Error => error
    @error = error
  end

  private

  def ask_paywall(page)
    if current_root_recording.blank? || current_user.blank?
      @paywall_error = "Choose a workspace before asking Jev."
      return
    end

    @paywall = page.analyze(:paywall, root_recording: current_root_recording, initiator: current_user)
  rescue RecordingStudioAI::Errors::ContractValidationError => error
    @paywall_error = error.code == "authorization" ? "You don't have access to ask Jev in this workspace." : undecided_message
  rescue RecordingStudioAI::Errors::ResolutionError
    @paywall_error = missing_jev_message
  rescue RecordingStudioAI::Errors::ExecutionError => error
    @paywall_error = error.message.include?("No candidates") ? missing_jev_message : undecided_message
  end

  def missing_jev_message
    "Jev is not configured. Set TYPESAFE_API_KEY."
  end

  def undecided_message
    "Jev could not decide."
  end
end
