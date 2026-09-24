# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class WebReaderHomeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "reader-test@example.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    sign_in @user
    Current.actor = @user
    workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    root = RecordingStudio.root_recording_for(workspace)
    grant_reader_access(root)
  ensure
    Current.actor = nil
  end

  test "home page renders the reader form" do
    get root_path

    assert_response :success
    assert_select "h1", text: "Web reader"
    assert_includes response.body, "Fetch a public page and inspect the normalized result."
    assert_includes response.body, "Probe image dimensions"
    assert_includes response.body, "Download the page"
    assert_includes response.body, "Open in a browser"
  end

  test "an unsafe url is shown as an observation error" do
    get root_path, params: { url: "http://127.0.0.1/secret" }

    assert_response :success
    assert_includes response.body, "The URL is not allowed"
    refute_includes response.body, "The page could not be fetched"
  end

  test "a stubbed page is rendered with metadata links and images" do
    html = <<~HTML
      <!doctype html>
      <html>
        <head>
          <title>Stubbed article</title>
          <meta name="description" content="Stubbed description">
          <link rel="canonical" href="https://example.com/canonical">
        </head>
        <body>
          <article>
            <p>Hello from the stub.</p>
            <a href="/about">About us</a>
            <img src="/photo.jpg" alt="Photo" width="640" height="480">
          </article>
        </body>
      </html>
    HTML
    response_body = Struct.new(:code, :headers, :body, keyword_init: true) do
      def each_header
        headers.each { |key, value| yield(key, value) }
      end

      def read_body
        yield body
      end
    end.new(
      code: 200,
      headers: { "content-type" => "text/html" },
      body: html
    )
    client = Object.new
    client.define_singleton_method(:ipaddr=) { |_value| nil }
    client.define_singleton_method(:use_ssl=) { |_value| nil }
    client.define_singleton_method(:verify_mode=) { |_value| nil }
    client.define_singleton_method(:open_timeout=) { |_value| nil }
    client.define_singleton_method(:read_timeout=) { |_value| nil }
    client.define_singleton_method(:write_timeout=) { |_value| nil }
    client.define_singleton_method(:max_retries=) { |_value| nil }
    client.define_singleton_method(:request) { |_req, &block| block.call(response_body) }

    captured = nil
    with_paywall(choice: :open, capture: ->(kwargs) { captured = kwargs }) do
      with_singleton_method(Resolv, :getaddresses, ->(*) { [ "93.184.216.34" ] }) do
        with_singleton_method(Net::HTTP, :new, ->(*) { client }) do
          get root_path, params: { url: "https://example.com/story" }
        end
      end
    end

    assert_response :success
    assert_includes response.body, "Stubbed article"
    assert_includes response.body, "Stubbed description"
    assert_includes response.body, "https://example.com/canonical"
    assert_includes response.body, "Hello from the stub."
    assert_includes response.body, "https://example.com/about"
    assert_includes response.body, "https://example.com/photo.jpg"
    assert_includes response.body, "html_attribute"
    assert_includes response.body, "No paywall"
    assert_includes response.body, "Jev read the visible text."
    assert_includes captured[:state], "Hello from the stub."
    assert_equal "page_paywall", captured[:purpose]
    refute_includes captured[:state], "<article>"
    refute_includes response.body, "Dummy paywall analysis"
    refute_includes response.body, "This response is a JavaScript challenge."
  end

  test "a read without a typesafe key says jev is not configured" do
    skip "This machine has a TypeSafe key" if ENV["TYPESAFE_API_KEY"].present?

    client = html_client("<html><title>Open article</title><body><article><p>The full story is here.</p></article></body></html>", status: 200)
    with_singleton_method(Resolv, :getaddresses, ->(*) { [ "93.184.216.34" ] }) do
      with_singleton_method(Net::HTTP, :new, ->(*) { client }) do
        get root_path, params: { url: "https://example.com/open" }
      end
    end

    assert_response :success
    assert_includes response.body, "The full story is here."
    assert_includes response.body, "Jev is not configured. Set TYPESAFE_API_KEY."
  end

  test "a javascript interstitial shows a challenge alert" do
    html = <<~HTML
      <html>
        <head><title>Just a moment...</title></head>
        <body>
          <noscript>Enable JavaScript and cookies to continue</noscript>
          <script src="/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1"></script>
        </body>
      </html>
    HTML
    client = html_client(html, status: 403)
    with_paywall(choice: :blocked) do
      with_singleton_method(Resolv, :getaddresses, ->(*) { [ "93.184.216.34" ] }) do
        with_singleton_method(Net::HTTP, :new, ->(*) { client }) do
          get root_path, params: { url: "https://example.com/challenge" }
        end
      end
    end

    assert_response :success
    assert_includes response.body, "This response is a JavaScript challenge."
    assert_includes response.body, "Enable JavaScript and cookies to continue"
    assert_includes response.body, "Just a moment..."
  end

  test "open in a browser uses the browser fetcher" do
    RecordingStudio::WebReader.register_fetcher(:browser, lambda { |hop|
      {
        status: 200,
        headers: { "content-type" => "text/html" },
        body: "<!doctype html><html><title>Browser article</title><body><article><p>Opened in the browser.</p></article></body></html>",
        content_type: "text/html",
        location: nil,
        address: hop[:address]
      }
    }, override: true)

    with_paywall(choice: :open) do
      with_singleton_method(Resolv, :getaddresses, ->(*) { [ "93.184.216.34" ] }) do
        get root_path, params: { url: "https://example.com/story", approach: "browser" }
      end
    end

    assert_response :success
    assert_includes response.body, "Browser article"
    assert_includes response.body, "Opened in the browser."
    assert_includes response.body, "Browser"
  ensure
    RecordingStudio::WebReader.register_fetcher(:browser, DummyBrowser, override: true)
  end

  private

  def grant_reader_access(root)
    return if RecordingStudioAccessible.authorized?(actor: @user, recording: root, role: :edit)

    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: root, actor: @user)
    return if result.success?

    admin = User.find_by(email: "admin@admin.com")
    return if admin.nil?

    Current.actor = admin
    RecordingStudioAccessible.grant_access(recording: root, actor: @user, role: :edit, manager_actor: admin)
  end

  def html_client(html, status:)
    response_body = Struct.new(:code, :headers, :body, keyword_init: true) do
      def each_header
        headers.each { |key, value| yield(key, value) }
      end

      def read_body
        yield body
      end
    end.new(code: status, headers: { "content-type" => "text/html" }, body: html)
    client = Object.new
    %i[ipaddr= use_ssl= verify_mode= open_timeout= read_timeout= write_timeout= max_retries=].each do |setter|
      client.define_singleton_method(setter) { |_value| nil }
    end
    client.define_singleton_method(:request) { |_req, &block| block.call(response_body) }
    client
  end

  def with_paywall(choice:, capture: nil)
    answer = Struct.new(:choice, :confidence, :probabilities).new(choice, 0.91, { choice.to_s => 0.91 })
    response = Struct.new(:answers).new({ paywall: answer })
    implementation = lambda { |**kwargs|
      capture&.call(kwargs)
      response
    }
    with_singleton_method(RecordingStudioAI, :decide!, implementation) do
      yield
    end
  end

  def with_singleton_method(object, name, implementation)
    singleton = object.singleton_class
    original = object.method(name)
    singleton.define_method(name, &implementation)
    yield
  ensure
    singleton.define_method(name) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
  end
end
