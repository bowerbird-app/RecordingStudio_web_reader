# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    @url = params[:url].to_s
    @probe = params[:probe] == "1"
    return if @url.blank?

    @page = RecordingStudio::WebReader.read(@url)
    @page = RecordingStudio::WebReader.probe_images(@page) if @probe
    @paywall = @page.analyze(:paywall)
  rescue RecordingStudio::WebReader::Error => error
    @error = error
  end
end
