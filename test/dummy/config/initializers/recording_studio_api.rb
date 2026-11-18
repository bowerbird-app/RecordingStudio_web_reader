# frozen_string_literal: true

return unless defined?(RecordingStudioApi)

RecordingStudioApi.configure do |config|
  # This dummy has no AdminRoot. API 1.15 skips the AdminApi declaration unless a
  # parent type is configured, so AdminApi is not registered as a recordable.
  config.admin_root_recordable_type_names = []
  config.rate_limit_oauth_enabled = false
  config.rate_limit_api_pre_auth_enabled = false
  config.rate_limit_api_enabled = false
  config.rate_limit_fail_closed = false
  config.api_management_authorization_required = false
end
