# frozen_string_literal: true

require "test_helper"

class WebReaderApiHttpTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.find_or_create_by!(email: "web-reader-http-owner@example.com") do |account|
      account.password = "Password"
      account.password_confirmation = "Password"
    end
    @root = DummyAccess.bootstrap_workspace!(name: "Web Reader HTTP Workspace", actor: @owner)
  end

  test "web_reader.read returns 200 for a token with view on the root" do
    RecordingStudio::WebReader.register_fetcher(:http, lambda { |hop|
      {
        status: 200,
        headers: { "content-type" => "text/html" },
        body: "<!doctype html><html><title>API article</title><body><article><p>Read through the API.</p></article></body></html>",
        content_type: "text/html",
        location: nil,
        address: hop[:address]
      }
    }, override: true)

    get "/recording_studio_api/api/v1/web_reader/read",
        params: { url: "https://example.com/article" },
        headers: bearer_headers(issue_token_for(@owner, @root).fetch(:token))

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "API article", payload.fetch("title")
    assert_equal "https://example.com/article", payload.fetch("url")
    assert_includes payload.fetch("text"), "Read through the API."
  ensure
    RecordingStudio::WebReader.register_fetcher(:http, RecordingStudio::WebReader::Http, override: true)
  end

  test "web_reader.read returns 401 without a token" do
    get "/recording_studio_api/api/v1/web_reader/read", params: { url: "https://example.com/article" }

    assert_response :unauthorized
  end

  test "web_reader.read returns 403 when the actor cannot view the root" do
    issued = issue_token_for(@owner, @root)
    RecordingStudio::Access.where(id: issued.fetch(:access_recording).recordable_id).update_all(role: "")
    refute RecordingStudioAccessible.authorized?(
      actor: issued.fetch(:access_recording).recordable.reload.actor,
      recording: @root,
      role: :view
    )

    get "/recording_studio_api/api/v1/web_reader/read",
        params: { url: "https://example.com/article" },
        headers: bearer_headers(issued.fetch(:token))

    assert_response :forbidden
  end

  test "web_reader.read returns 422 for a blocked url" do
    get "/recording_studio_api/api/v1/web_reader/read",
        params: { url: "http://127.0.0.1/secret" },
        headers: bearer_headers(issue_token_for(@owner, @root).fetch(:token))

    assert_response :unprocessable_entity
  end

  test "web_reader.read returns 422 for a bad url" do
    get "/recording_studio_api/api/v1/web_reader/read",
        params: { url: "not-a-url" },
        headers: bearer_headers(issue_token_for(@owner, @root).fetch(:token))

    assert_response :unprocessable_entity
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def access_recording_for(actor, root)
    RecordingStudioAccessible.access_recordings_for_actor(recording: root, actor: actor).first
  end

  def issue_token_for(actor, root)
    access_recording = access_recording_for(actor, root)
    raise "missing access recording" if access_recording.blank?

    provision = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: root,
      manager_actor: actor,
      role: access_recording.recordable.role,
      name: "Web reader HTTP client #{SecureRandom.hex(4)}"
    )
    raise provision.error unless provision.success?

    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: provision.value.fetch(:credential).oauth_client_id,
      client_secret: provision.value.fetch(:token)
    )
    raise token_result.error unless token_result.success?

    {
      token: token_result.value.fetch(:access_token),
      access_recording: provision.value.fetch(:access_recording)
    }
  end
end
