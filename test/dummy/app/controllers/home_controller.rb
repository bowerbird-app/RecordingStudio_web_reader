# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    @url = params[:url].to_s
    @probe = params[:probe] == "1"
    @approach = params[:approach] == "browser" ? "browser" : "download"
    return if @url.blank?

    @page = RecordingStudio::WebReader.read(@url, strategy: @approach == "browser" ? :browser : :http)
    @page = RecordingStudio::WebReader.probe_images(@page) if @probe
    @paywall = @page.analyze(:paywall)
  rescue RecordingStudio::WebReader::Error => error
    @error = error
  end
end
