# frozen_string_literal: true

return unless defined?(RecordingStudioApi)

RecordingStudioApi.configure do |config|
  # This dummy has no AdminRoot. Empty parents so eager-loaded AdminApi can declare.
  config.admin_root_recordable_type_names = []
  config.rate_limit_oauth_enabled = false
  config.rate_limit_api_pre_auth_enabled = false
  config.rate_limit_api_enabled = false
  config.rate_limit_fail_closed = false
  config.api_management_authorization_required = false
end

Rails.application.config.to_prepare do
  RecordingStudioApi::AdminApi
end
