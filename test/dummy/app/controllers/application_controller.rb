class ApplicationController < ActionController::Base
  include RecordingStudio::RootSwitchable::ControllerSupport

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  recording_studio_layout do
    if devise_controller?
      "application"
    else
      RecordingStudio::WebReader.configuration.layout
    end
  end

  before_action :authenticate_user!
  before_action :set_current_actor

  private

  def set_current_actor
    Current.actor = current_user
  end
end
