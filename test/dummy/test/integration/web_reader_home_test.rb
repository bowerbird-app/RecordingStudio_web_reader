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
  end

  test "home page renders the reader form" do
    get root_path

    assert_response :success
    assert_select "h1", text: "Web reader"
    assert_includes response.body, "Fetch a public page and inspect the normalized result."
    assert_includes response.body, "Probe image dimensions"
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

    with_singleton_method(Resolv, :getaddresses, ->(*) { ["93.184.216.34"] }) do
      with_singleton_method(Net::HTTP, :new, ->(*) { client }) do
        get root_path, params: { url: "https://example.com/story" }
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
    assert_includes response.body, "Dummy paywall analysis"
  end

  private

  def with_singleton_method(object, name, implementation)
    singleton = object.singleton_class
    original = object.method(name)
    singleton.define_method(name, &implementation)
    yield
  ensure
    singleton.define_method(name) { |*args, &block| original.call(*args, &block) }
  end
end
