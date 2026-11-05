# frozen_string_literal: true

module RecordingStudio
  module WebReader
    class ApplicationController < ActionController::Base
      protect_from_forgery with: :exception

      recording_studio_layout { RecordingStudio::WebReader.configuration.layout }
    end
  end
end
