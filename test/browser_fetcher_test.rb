# frozen_string_literal: true

require "test_helper"
require "socket"

class BrowserFetcherTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudio::WebReader.instance_variable_get(:@configuration)
    @original_registry = RecordingStudio::WebReader.instance_variable_get(:@registry)
    RecordingStudio::WebReader.instance_variable_set(
      :@configuration,
      RecordingStudio::WebReader::Configuration.new
    )
    RecordingStudio::WebReader.instance_variable_set(:@registry, nil)
  end

  def teardown
    RecordingStudio::WebReader.instance_variable_set(:@configuration, @original_configuration)
    RecordingStudio::WebReader.instance_variable_set(:@registry, @original_registry)
  end

  def test_the_gem_registers_the_browser_fetcher
    names = RecordingStudio::WebReader.extensions

    assert(names.any? { |row| row[:kind] == :fetcher && row[:name] == :http })
    assert(names.any? { |row| row[:kind] == :fetcher && row[:name] == :browser })
  end

  def test_registering_the_browser_again_requires_override
    RecordingStudio::WebReader.extensions

    error = assert_raises(RecordingStudio::WebReader::RegistryError) do
      RecordingStudio::WebReader.register_fetcher(:browser, ->(*) { {} })
    end

    assert_equal "fetcher browser is already registered", error.message
  end

  def test_a_host_that_rewrites_the_resolver_rule_is_refused
    bad_hop = hop("http://example.com/").merge(host: "example.com, MAP evil.com 127.0.0.1")

    error = assert_raises(RecordingStudio::WebReader::FetchError) do
      RecordingStudio::WebReader::Browser.call(bad_hop)
    end

    assert_equal "The page could not be fetched", error.message
  end

  def test_a_missing_browser_is_a_fetch_error
    File.stub(:executable?, false) do
      error = assert_raises(RecordingStudio::WebReader::FetchError) do
        RecordingStudio::WebReader::Browser.call(hop("http://example.com/"))
      end
      assert_equal "A browser is not available on this machine", error.message
    end
  end

  def test_binary_path_uses_chrome_path_before_the_environment
    RecordingStudio::WebReader.configuration.chrome_path = "/opt/chrome"
    original = ENV.fetch("GOOGLE_CHROME_BIN", nil)
    ENV["GOOGLE_CHROME_BIN"] = "/env/chrome"

    File.stub(:executable?, ->(path) { path == "/opt/chrome" }) do
      assert_equal "/opt/chrome", RecordingStudio::WebReader::Browser.binary_path
    end
  ensure
    restore_chrome_bin(original)
  end

  def test_private_document_requests_are_refused_and_redirects_are_returned
    private_document = decision_for(
      { "request" => { "url" => "http://127.0.0.1/secret" }, "resourceType" => "Document" }
    )
    assert_equal :block, private_document.action
    assert_instance_of RecordingStudio::WebReader::UnsafeUrlError, private_document.error

    private_script = decision_for(
      { "request" => { "url" => "http://169.254.169.254/latest/meta-data/" }, "resourceType" => "Script" }
    )
    assert_equal :block, private_script.action
    assert_nil private_script.error

    redirect = decision_for(
      {
        "responseStatusCode" => 302,
        "responseHeaders" => [{ "name" => "Location", "value" => "https://cdn.example.com/a" }],
        "resourceType" => "Document",
        "request" => { "url" => "https://example.com/start" }
      }
    )
    assert_equal :redirect, redirect.action
    assert_equal 302, redirect.exchange[:status]
    assert_equal "https://cdn.example.com/a", redirect.exchange[:location]

    follow_up = decision_for(
      { "request" => { "url" => "https://cdn.example.com/a" }, "resourceType" => "Document" },
      redirect_captured: true
    )
    assert_equal :fail, follow_up.action
  end

  def test_the_approved_hop_is_not_looked_up_again
    decision = Resolv.stub(:getaddresses, ->(*) { raise Resolv::ResolvError }) do
      decision_for(
        { "request" => { "url" => "https://example.com/a" }, "resourceType" => "Document" },
        hop_url: "https://example.com/a"
      )
    end

    assert_equal :continue, decision.action
  end

  def test_browser_strategy_follows_a_redirect_without_using_http
    hops = []
    responses = [
      {
        status: 302,
        headers: { "location" => "https://cdn.example.com/article" },
        body: "",
        content_type: "text/html",
        location: "https://cdn.example.com/article"
      },
      {
        status: 200,
        headers: { "content-type" => "text/html" },
        body: "<html><title>Landed</title><body><article><p>Landed safely.</p></article></body></html>",
        content_type: "text/html",
        location: nil
      }
    ]

    page = with_browser_responses(responses, hops) do
      RecordingStudio::WebReader.read("https://example.com/start", strategy: :browser)
    end

    assert_equal "Landed", page.title
    assert_equal "https://cdn.example.com/article", page.final_url
    hosts = hops.map { |item| item[:host] }
    addresses = hops.map { |item| item[:address] }
    assert_equal %w[example.com cdn.example.com], hosts
    assert_equal ["93.184.216.34", "93.184.216.35"], addresses
  end

  def test_a_browser_redirect_to_a_private_address_is_rejected
    calls = 0
    response = {
      status: 302,
      headers: { "location" => "http://127.0.0.1/secret" },
      body: "",
      content_type: "text/html",
      location: "http://127.0.0.1/secret"
    }

    Resolv.stub(:getaddresses, ["93.184.216.34"]) do
      Net::HTTP.stub(:new, ->(*) { flunk "HTTP fetcher ran" }) do
        RecordingStudio::WebReader::Browser.stub(:call, lambda { |item|
          calls += 1
          response.merge(address: item[:address])
        }) do
          assert_raises(RecordingStudio::WebReader::UnsafeUrlError) do
            RecordingStudio::WebReader.read("https://example.com/start", strategy: :browser)
          end
        end
      end
    end

    assert_equal 1, calls
  end

  def test_chrome_renders_html_stops_before_a_redirect_and_blocks_a_private_document
    skip "Chrome is not installed" unless RecordingStudio::WebReader::Browser.binary_path

    with_page_server do |server|
      rendered = RecordingStudio::WebReader::Browser.call(server.hop("/article"))
      assert_equal 200, rendered[:status]
      assert_includes rendered[:body], "Rendered article"
      assert_equal server.address, rendered[:address]

      redirect = RecordingStudio::WebReader::Browser.call(server.hop("/jump"))
      assert_equal 302, redirect[:status]
      assert_includes redirect[:location].to_s, "/landed"
      refute_includes redirect[:body].to_s, "Landed page"
      refute_includes server.paths, "/landed"

      visible = RecordingStudio::WebReader::Browser.call(server.hop("/spy"))
      assert_includes visible[:body], "Visible article"
      refute_includes server.paths, "/sneak"

      error = assert_raises(RecordingStudio::WebReader::UnsafeUrlError) do
        RecordingStudio::WebReader::Browser.call(server.hop("/escape"))
      end
      assert_equal "The URL is not allowed", error.message
    end
  end

  private

  def decision_for(params, redirect_captured: false, hop_url: nil)
    RecordingStudio::WebReader::Browser.decision_for(params, redirect_captured:, hop_url:)
  end

  def hop(url)
    {
      url: url,
      address: "93.184.216.34",
      host: "example.com",
      port: 80,
      https: false,
      timeouts: { open: 1, read: 1, write: 1 },
      max_bytes: 2_000_000,
      user_agent: "RecordingStudioWebReaderTest",
      on_overflow: :raise
    }
  end

  def with_browser_responses(responses, hops, &block)
    addresses = lambda { |host|
      case host
      when "example.com" then ["93.184.216.34"]
      when "cdn.example.com" then ["93.184.216.35"]
      else flunk("unexpected host #{host}")
      end
    }
    fetcher = lambda { |item|
      hops << item
      responses.shift.merge(address: item[:address])
    }
    Resolv.stub(:getaddresses, addresses) do
      Net::HTTP.stub(:new, ->(*) { flunk "HTTP fetcher ran" }) do
        RecordingStudio::WebReader::Browser.stub(:call, fetcher, &block)
      end
    end
  end

  def restore_chrome_bin(original)
    if original
      ENV["GOOGLE_CHROME_BIN"] = original
    else
      ENV.delete("GOOGLE_CHROME_BIN")
    end
  end

  def with_page_server
    server = PageServer.new
    yield server
  ensure
    server&.stop
  end

  class PageServer
    attr_reader :port

    def initialize
      @requests = Queue.new
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @thread = Thread.new { serve }
    end

    def address
      "127.0.0.1"
    end

    def hop(path)
      {
        url: "http://example.com:#{port}#{path}",
        address: address,
        host: "example.com",
        port: port,
        https: false,
        timeouts: { open: 15, read: 20, write: 5 },
        max_bytes: 2_000_000,
        user_agent: "RecordingStudioWebReaderTest",
        on_overflow: :raise
      }
    end

    def paths
      drain = []
      drain << @requests.pop(true) until @requests.empty?
      @seen = Array(@seen) + drain
      @seen.dup
    end

    def stop
      @server.close
      @thread.join(2)
    rescue StandardError
      nil
    end

    private

    def serve
      loop do
        client = @server.accept
        handle(client)
      end
    rescue StandardError
      nil
    end

    def handle(client)
      request = +""
      while (line = client.gets)
        request << line
        break if line == "\r\n"
      end
      path = request.lines.first.to_s.split[1].to_s.split("?").first
      @requests << path
      status, extra, body = route(path)
      client.write(response_for(status, extra, body))
    ensure
      client&.close
    end

    def route(path)
      case path
      when "/article" then ["200 OK", "", html("Rendered article")]
      when "/jump" then ["302 Found", "Location: http://example.com:#{port}/landed\r\n", ""]
      when "/landed" then ["200 OK", "", html("Landed page")]
      when "/spy" then ["200 OK", "", html("Visible article", "<img src=\"http://127.0.0.1:#{port}/sneak\">")]
      when "/escape" then ["200 OK", "", html("Leave", "<script>location = \"http://127.0.0.1:#{port}/sneak\"</script>")]
      when "/sneak" then ["200 OK", "", "secret"]
      else ["404 Not Found", "", ""]
      end
    end

    def html(text, extra = "")
      "<!doctype html><html><title>#{text}</title><body><article><p>#{text}</p>#{extra}</article></body></html>"
    end

    def response_for(status, extra, body)
      "HTTP/1.1 #{status}\r\nContent-Type: text/html\r\nContent-Length: #{body.bytesize}\r\n" \
        "Connection: close\r\n#{extra}\r\n#{body}"
    end
  end
end
