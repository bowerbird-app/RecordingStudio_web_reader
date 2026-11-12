# frozen_string_literal: true

require "test_helper"
require "recording_studio_api"

class ApiTest < Minitest::Test
  class FakeGrant
    def initialize(authorized: true)
      @authorized = authorized
    end

    def authorize!(recording:, role:, **)
      raise "API access grant is not authorized for this capability" unless @authorized
      raise "view role required" unless role == :view
      raise "root recording required" if recording.nil?
    end
  end

  class FakeRoot
    def id
      1
    end
  end

  class FakeContext
    def initialize(params: {}, root_recording: FakeRoot.new, authorized: true)
      @access_grant = FakeGrant.new(authorized: authorized)
      @params = params
      @root_recording = root_recording
    end

    attr_reader :access_grant, :params, :root_recording
  end

  def test_register_is_a_noop_when_api_is_unavailable
    RecordingStudio::WebReader::Api.stub(:available?, false) do
      assert_nil RecordingStudio::WebReader::Api.register!
    end
  end

  def test_gemspec_omits_runtime_recording_studio_api_dependency
    gemspec = File.read(File.expand_path("../recording_studio_web_reader.gemspec", __dir__))
    gemfile = File.read(File.expand_path("../Gemfile", __dir__))
    dummy_gemfile = File.read(File.expand_path("dummy/Gemfile", __dir__))

    refute_includes gemspec, 'spec.add_dependency "recording_studio_api"'
    refute_includes gemspec, 'spec.add_development_dependency "recording_studio_api"'
    assert_includes gemfile, "recording_studio_api"
    assert_includes dummy_gemfile, 'tag: "v0.21.3"'
    assert_includes dummy_gemfile, "group :development, :test"
  end

  def test_engine_registers_api_when_present
    engine = File.read(File.expand_path("../lib/recording_studio_web_reader/engine.rb", __dir__))
    api = File.read(File.expand_path("../lib/recording_studio_web_reader/api.rb", __dir__))
    read = File.read(File.expand_path("../lib/recording_studio_web_reader/api/read.rb", __dir__))

    assert_includes engine, 'initializer "recording_studio_web_reader.api"'
    assert_includes engine, "RecordingStudio::WebReader::Api.register!"
    assert_includes api, "RecordingStudioApi.register_endpoint"
    assert_includes api, "return unless available?"
    assert_includes api, "each_api"
    assert_includes api, "NAME = \"web_reader.read\""
    assert_includes api, "handler: Read"
    assert_includes api, "http_verb: :get"
    assert_includes api, "path: PATH"
    assert_includes api, "PATH = \"web_reader/read\""
    assert_includes api, 'title: "Web Reader - Read"'
    assert_includes api, 'summary: "Web Reader - Read"'
    assert_includes api, "reject_unknown: false"
    refute_includes api, "register_capability_action"
    refute File.exist?(File.expand_path("../lib/recording_studio_web_reader/mcp.rb", __dir__))
    assert_includes read, "grant.authorize!"
    assert_includes read, "RecordingStudio::WebReader.read"
    assert_includes read, "role: VIEW_ROLE"
    assert_includes read, "InvalidActionInputError"
    refute_includes read, "Pundit"
    refute_includes read, "probe_image"
    refute_includes read, "extract("
    refute_includes read, "analyze("
  end

  def test_read_registration_is_idempotent
    registrations = []
    RecordingStudioApi.stub(:registered_endpoint, ->(*) { registrations.first }) do
      RecordingStudioApi.stub(:register_endpoint, lambda { |name, **options|
        registrations << { name: name, **options }
      }) do
        RecordingStudio::WebReader::Api.stub(:each_api_name, ->(&block) { block.call(:public) }) do
          2.times { RecordingStudio::WebReader::Api.register! }
        end
      end
    end

    names = registrations.map { |entry| entry.fetch(:name) }
    assert_equal ["web_reader.read"], names
    registration = registrations.first
    assert_equal :get, registration.fetch(:http_verb)
    assert_equal "web_reader/read", registration.fetch(:path)
    assert_equal RecordingStudio::WebReader::Api::Read, registration.fetch(:handler)
    assert_equal :public, registration.fetch(:api)
  end

  def test_read_returns_page_when_authorized
    page = RecordingStudio::WebReader::Page.new(
      url: "https://example.com/article",
      final_url: "https://example.com/article",
      status: 200,
      headers: { "content-type" => "text/html" },
      content_type: "text/html",
      title: "Stubbed article",
      description: "Stubbed description",
      canonical_url: "https://example.com/article",
      text: "Hello from the stub.",
      html: "<html></html>",
      metadata: RecordingStudio::WebReader::Page::Metadata.new(
        open_graph: {},
        twitter: {},
        json_ld: [],
        article: {},
        meta: {}
      ),
      links: [],
      images: [],
      challenge: nil
    )
    captured = {}

    RecordingStudio::WebReader.stub(:read, lambda { |url, **kwargs|
      captured[:url] = url
      captured[:kwargs] = kwargs
      page
    }) do
      payload = RecordingStudio::WebReader::Api::Read.call(
        FakeContext.new(params: { url: "https://example.com/article", strategy: "http" })
      )

      assert_equal "Stubbed article", payload.fetch("title")
      assert_equal "https://example.com/article", payload.fetch("url")
    end

    assert_equal "https://example.com/article", captured[:url]
    assert_equal({ strategy: "http" }, captured[:kwargs])
  end

  def test_read_denies_unauthorized_callers
    error = assert_raises(RuntimeError) do
      RecordingStudio::WebReader::Api::Read.call(
        FakeContext.new(params: { url: "https://example.com/article" }, authorized: false)
      )
    end

    assert_match(/not authorized/, error.message)
  end

  def test_read_requires_a_root_recording
    error = assert_raises(RuntimeError) do
      RecordingStudio::WebReader::Api::Read.call(
        FakeContext.new(params: { url: "https://example.com/article" }, root_recording: nil)
      )
    end

    assert_match(/root recording required/, error.message)
  end

  def test_read_maps_blocked_urls_to_invalid_input
    error = assert_raises(RecordingStudioApi::InvalidActionInputError) do
      RecordingStudio::WebReader::Api::Read.call(
        FakeContext.new(params: { url: "http://127.0.0.1/secret" })
      )
    end

    assert_equal "The URL is not allowed", error.message
  end
end
