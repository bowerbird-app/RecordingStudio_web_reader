# frozen_string_literal: true

require "test_helper"
require "zlib"
require_relative "support/web_reader_http"

class WebReaderBehaviorTest < Minitest::Test
  include WebReaderHttp

  ARTICLE_HTML = <<~HTML
    <!doctype html>
    <html>
      <head>
        <title>Example Article</title>
        <meta name="description" content="A short description">
        <link rel="canonical" href="/canonical">
        <meta property="og:title" content="OG Title">
        <meta property="og:description" content="OG description">
        <meta property="og:image" content="/hero.jpg">
        <meta property="og:image:width" content="1600">
        <meta property="og:image:height" content="900">
        <meta name="twitter:card" content="summary_large_image">
        <meta name="twitter:title" content="Twitter Title">
        <meta name="twitter:image" content="https://cdn.example.com/tw.jpg">
        <meta name="author" content="Ada Lovelace">
        <meta property="article:published_time" content="2024-01-02">
        <script type="application/ld+json">
          {"@type":"NewsArticle","headline":"Example Article","author":{"@type":"Person","name":"Ada Lovelace"}}
        </script>
        <script type="application/ld+json; charset=utf-8">[{"@type":"BreadcrumbList"}, "skip-me"]</script>
        <script type="application/ld+json">{not json</script>
      </head>
      <body>
        <nav>Site menu SECRET-NAV</nav>
        <header>Masthead</header>
        <article>
          <h1>Hello</h1>
          <p>Main paragraph.</p>
          <a href="/about" rel="author noopener">About us</a>
          <a href="javascript:void(0)">Script link</a>
          <a href="mailto:ada@example.com">Mail</a>
          <a href="http://127.0.0.1/local">Local observation</a>
          <img src="/photo.jpg" alt="Photo" width="1600" height="900" srcset="/photo-640.jpg 640w, /photo-1200.jpg 1200w, /photo-2x.jpg 2x">
          <img data-src="/lazy.jpg" alt="Lazy photo">
          <img srcset="/only-640.jpg 640w" alt="Srcset only">
          <img src="data:image/gif;base64,AAAA" alt="pixel">
        </article>
        <aside>Related SECRET-ASIDE</aside>
        <footer>Footer legal</footer>
      </body>
    </html>
  HTML

  def setup
    @original_configuration = RecordingStudio::WebReader.instance_variable_get(:@configuration)
    RecordingStudio::WebReader.instance_variable_set(
      :@configuration,
      RecordingStudio::WebReader::Configuration.new
    )
    RecordingStudio::WebReader.reset_extensions!
  end

  def teardown
    RecordingStudio::WebReader.reset_extensions!
    RecordingStudio::WebReader.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_read_returns_a_normalized_page_for_ordinary_html
    page, log = read_page("https://example.com/article#part", [html_response(ARTICLE_HTML, headers: {
                                                                               "set-cookie" => "session=SECRET-COOKIE",
                                                                               "authorization" => "Bearer SECRET-AUTH"
                                                                             })])

    assert_instance_of RecordingStudio::WebReader::Page, page
    assert_equal "https://example.com/article#part", page.url
    assert_equal "https://example.com/article", page.final_url
    assert_equal 200, page.status
    assert_equal "text/html", page.content_type
    assert_equal "Example Article", page.title
    assert_equal "A short description", page.description
    assert_equal "https://example.com/canonical", page.canonical_url
    assert_includes page.text, "Main paragraph."
    refute_includes page.text, "SECRET-NAV"
    refute_includes page.text, "Footer legal"
    refute_includes page.text, "SECRET-ASIDE"
    assert_includes page.html, "SECRET-NAV"
    refute page.headers.key?("set-cookie")
    refute page.headers.key?("authorization")
    assert_equal "utf-8", page.headers["content-type"].split("charset=").last
    assert_equal "OG Title", page.metadata.open_graph["title"]
    assert_equal "summary_large_image", page.metadata.twitter["card"]
    assert_equal "Twitter Title", page.metadata.twitter["title"]
    assert_equal "Ada Lovelace", page.metadata.article["author"]
    assert_equal "2024-01-02", page.metadata.article["published_time"]
    assert_equal "A short description", page.metadata.meta["description"]
    assert_equal "NewsArticle", page.metadata.json_ld[0]["@type"]
    assert_equal "BreadcrumbList", page.metadata.json_ld[1]["@type"]
    assert_equal 2, page.metadata.json_ld.length

    about = page.links.find { |link| link[:text] == "About us" }
    assert_equal "https://example.com/about", about[:url]
    assert_equal %w[author noopener], about[:rel]
    refute(page.links.any? { |link| link[:url].start_with?("javascript:") })
    refute(page.links.any? { |link| link[:url].start_with?("mailto:") })
    local = page.links.find { |link| link[:text] == "Local observation" }
    assert_equal "http://127.0.0.1/local", local[:url]

    photo = page.images.find { |image| image[:alt] == "Photo" }
    assert_equal "https://example.com/photo.jpg", photo[:url]
    assert_equal 1600, photo[:width]
    assert_equal 900, photo[:height]
    assert_equal 1.778, photo[:aspect_ratio]
    assert_equal :html_attribute, photo[:source]
    assert_equal :html_attribute, photo[:dimension_source]
    assert_equal [
      { url: "https://example.com/photo-640.jpg", width_hint: 640 },
      { url: "https://example.com/photo-1200.jpg", width_hint: 1200 },
      { url: "https://example.com/photo-2x.jpg", width_hint: nil }
    ], photo[:variants]

    lazy = page.images.find { |image| image[:alt] == "Lazy photo" }
    assert_equal "https://example.com/lazy.jpg", lazy[:url]
    assert_equal :lazy_attribute, lazy[:source]
    assert_nil lazy[:dimension_source]

    srcset = page.images.find { |image| image[:alt] == "Srcset only" }
    assert_equal "https://example.com/only-640.jpg", srcset[:url]
    assert_equal :srcset, srcset[:source]

    hero = page.images.find { |image| image[:url] == "https://example.com/hero.jpg" }
    assert_equal :open_graph, hero[:source]
    assert_equal 1600, hero[:width]
    assert_equal :html_attribute, hero[:dimension_source]

    twitter = page.images.find { |image| image[:url] == "https://cdn.example.com/tw.jpg" }
    assert_equal :twitter, twitter[:source]
    assert_nil twitter[:width]
    refute(page.images.any? { |image| image[:url].start_with?("data:") })

    assert_equal 1, log.length
    assert_equal "93.184.216.34", log.first[:ipaddr]
    assert_equal true, log.first[:use_ssl]
    assert_equal OpenSSL::SSL::VERIFY_PEER, log.first[:verify_mode]
    assert_equal "RecordingStudioWebReader/#{RecordingStudio::WebReader::VERSION}", log.first[:user_agent]
    assert_nil log.first[:range]
    assert_equal 5, log.first[:open_timeout]
    assert_equal 10, log.first[:read_timeout]

    payload = JSON.generate(page.to_h)
    parsed = JSON.parse(payload)
    assert_equal "html_attribute", parsed.dig("images", 0, "dimension_source")
    assert_equal "html_attribute", parsed.dig("images", 0, "source")
    assert_nil page.challenge
    assert_nil parsed["challenge"]
    restored = RecordingStudio::WebReader::Page.from_h(parsed)
    assert_equal :html_attribute, restored.images.first[:dimension_source]
    assert_equal "Example Article", restored.title
    assert_nil restored.challenge
    parsed.delete("challenge")
    assert_nil RecordingStudio::WebReader::Page.from_h(parsed).challenge
  end

  def test_description_falls_back_to_open_graph
    html = "<!doctype html><html><head><meta property=\"og:description\" content=\"From Open Graph\">" \
           "</head><body><p>Hi</p></body></html>"
    page, = read_page("https://example.com/", [html_response(html)])

    assert_equal "From Open Graph", page.description
  end

  def test_missing_content_type_is_html_when_the_body_looks_like_html
    response = Response.new(code: 200, headers: {},
                            body: "<!doctype html><html><title>Bare</title><body><p>Bare body</p></body></html>")
    page, = read_page("https://example.com/", [response])

    assert_equal "text/html", page.content_type
    assert_equal "Bare", page.title
  end

  def test_redirect_keeps_the_requested_url_and_uses_the_final_document
    landed = "<!doctype html><html><head><title>Landed</title>" \
             "<link rel=\"canonical\" href=\"/final-canon\"></head>" \
             "<body><article><p>Landed text</p></article></body></html>"
    page, log = read_page(
      "https://example.com/start",
      [redirect_response("/landed"), html_response(landed)]
    )

    assert_equal "https://example.com/start", page.url
    assert_equal "https://example.com/landed", page.final_url
    assert_equal "https://example.com/final-canon", page.canonical_url
    assert_equal "Landed", page.title
    assert_equal 200, page.status
    assert_equal 2, log.length
    assert_equal "/landed", log.last[:path]
  end

  def test_http_statuses_are_observations
    [403, 404, 500].each do |status|
      html = "<!doctype html><html><title>Status #{status}</title><body><p>Status body #{status}</p></body></html>"
      page, = read_page("https://example.com/missing", [html_response(html, status: status)])

      assert_equal status, page.status
      assert_includes page.text, "Status body #{status}"
      assert_nil page.challenge
    end
  end

  def test_read_keeps_noscript_text_when_the_page_has_no_other_text
    html = <<~HTML
      <html><body><div role="main"><noscript>Enable JavaScript and cookies to continue</noscript></div></body></html>
    HTML
    page, = read_page("https://example.com/challenge", [html_response(html, status: 403)])

    assert_equal 403, page.status
    assert_equal "Enable JavaScript and cookies to continue", page.text
    assert_equal :javascript, page.challenge.kind
    noscript = page.challenge.evidence.find { |item| item.path == "noscript" }
    assert_equal "Enable JavaScript and cookies to continue", noscript.value
  end

  def test_read_skips_noscript_when_visible_text_exists
    html = <<~HTML
      <html><body><article><p>Visible story</p></article><noscript>Enable JavaScript</noscript></body></html>
    HTML
    page, = read_page("https://example.com/story", [html_response(html)])

    assert_equal "Visible story", page.text
    assert_nil page.challenge
  end

  def test_javascript_interstitial_records_challenge_evidence
    html = <<~HTML
      <html>
        <head><title>Just a moment...</title></head>
        <body>
          <div role="main"><noscript>Enable JavaScript and cookies to continue</noscript></div>
          <script src="/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1"></script>
        </body>
      </html>
    HTML
    page, = read_page("https://example.com/challenge", [html_response(html, status: 403)])
    payload = JSON.parse(JSON.generate(page.to_h))
    restored = RecordingStudio::WebReader::Page.from_h(payload)

    assert_equal :javascript, page.challenge.kind
    assert_equal "/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1", evidence_value(page, "script")
    assert_equal "Just a moment...", evidence_value(page, "title")
    assert_equal "Enable JavaScript and cookies to continue", evidence_value(page, "noscript")
    assert_equal 403, evidence_value(page, "status")
    assert_equal "javascript", payload.dig("challenge", "kind")
    assert_equal :javascript, restored.challenge.kind
    assert_equal :html, restored.challenge.evidence.find { |item| item.path == "script" }.source
    assert page.to_h.key?("html")
  end

  def test_challenge_script_marks_a_page_without_an_interstitial_title
    html = "<html><body><p>Please wait</p>" \
           "<iframe src=\"https://challenges.cloudflare.com/cdn-cgi/challenge-platform\"></iframe></body></html>"
    page, = read_page("https://example.com/wait", [html_response(html)])

    assert_equal :javascript, page.challenge.kind
    assert_equal "https://challenges.cloudflare.com/cdn-cgi/challenge-platform", evidence_value(page, "script")
    assert_nil(page.challenge.evidence.find { |item| item.path == "title" })
  end

  def test_interstitial_title_without_a_javascript_request_is_a_document
    html = "<html><head><title>Just a moment...</title></head>" \
           "<body><article><p>A real essay.</p></article></body></html>"
    page, = read_page("https://example.com/essay", [html_response(html, status: 403)])

    assert_equal "A real essay.", page.text
    assert_nil page.challenge
  end

  def test_non_html_response_raises_with_status
    response = Response.new(
      code: 404,
      headers: { "content-type" => "application/json" },
      body: "{\"error\":\"SECRET-BODY\"}"
    )
    error = assert_raises(RecordingStudio::WebReader::UnsupportedContentTypeError) do
      read_page("https://example.com/data", [response])
    end

    assert_equal 404, error.status
    refute_includes error.message, "SECRET-BODY"
  end

  def test_timeout_is_a_fetch_error_without_the_original_message
    error = assert_raises(RecordingStudio::WebReader::TimeoutError) do
      read_page("https://example.com/", [Timeout::Error.new("token=SECRET-TIMEOUT")])
    end

    assert_kind_of RecordingStudio::WebReader::FetchError, error
    assert_equal "The request timed out", error.message
    refute_includes error.message, "SECRET-TIMEOUT"
  end

  def test_socket_errors_become_fetch_errors
    error = assert_raises(RecordingStudio::WebReader::FetchError) do
      read_page("https://example.com/", [SocketError.new("SECRET-SOCKET")])
    end

    refute_kind_of RecordingStudio::WebReader::TimeoutError, error
    refute_includes error.message, "SECRET-SOCKET"
  end

  def test_too_many_redirects
    RecordingStudio::WebReader.configuration.max_redirects = 1
    error = assert_raises(RecordingStudio::WebReader::TooManyRedirectsError) do
      read_page(
        "https://example.com/start",
        [redirect_response("/one"), redirect_response("/two")]
      )
    end

    assert_equal "The page redirected too many times", error.message
  end

  def test_redirect_without_a_location_is_a_fetch_error
    response = Response.new(code: 302, headers: { "content-type" => "text/html" }, body: "SECRET-REDIRECT")
    error = assert_raises(RecordingStudio::WebReader::FetchError) do
      read_page("https://example.com/start", [response])
    end

    refute_includes error.message, "SECRET-REDIRECT"
  end

  def test_oversized_content_length_is_rejected_before_the_body
    RecordingStudio::WebReader.configuration.max_response_bytes = 10
    response = Response.new(
      code: 200,
      headers: { "content-type" => "text/html", "content-length" => "50" },
      body: "0123456789SECRET-OVERFLOW",
      refuse_body: true
    )

    assert_raises(RecordingStudio::WebReader::ResponseTooLargeError) do
      read_page("https://example.com/", [response])
    end
  end

  def test_oversized_body_without_content_length_is_rejected
    RecordingStudio::WebReader.configuration.max_response_bytes = 8
    response = Response.new(
      code: 200,
      headers: { "content-type" => "text/html" },
      body: "0123456789SECRET"
    )

    assert_raises(RecordingStudio::WebReader::ResponseTooLargeError) do
      read_page("https://example.com/", [response])
    end
  end

  def test_http_truncates_a_probe_body
    called = false
    response = Response.new(code: 200, headers: { "content-type" => "image/png" }, body: "abcdefghij")
    response.define_singleton_method(:read_body) do |&block|
      called = true
      block.call("abcdefghij")
    end
    log = []
    client = Client.new([response], log)
    hop = {
      url: "https://example.com/a.png",
      address: "93.184.216.34",
      host: "example.com",
      port: 443,
      https: true,
      timeouts: { open: 1, read: 1, write: 1 },
      max_bytes: 4,
      user_agent: "tester",
      on_overflow: :truncate,
      range: "bytes=0-3"
    }
    result = Net::HTTP.stub(:new, client) do
      RecordingStudio::WebReader::Http.call(hop)
    end

    assert called
    assert_equal "abcd", result[:body]
    assert_equal "bytes=0-3", log.first[:range]
    assert_equal OpenSSL::SSL::VERIFY_PEER, log.first[:verify_mode]
  end

  def test_plain_http_does_not_pretend_to_verify_tls
    response = html_response("<!doctype html><html><title>Clear</title><body><p>Clear</p></body></html>")
    _page, log = read_page("http://example.com/page", [response])

    assert_equal false, log.first[:use_ssl]
    assert_nil log.first[:verify_mode]
    assert_equal "/page", log.first[:path]
  end

  def test_unsupported_schemes_and_blank_urls
    ["file:///etc/passwd", "ftp://example.com/a", "javascript:alert(1)", "not a url", ""].each do |url|
      assert_raises(RecordingStudio::WebReader::InvalidUrlError) do
        RecordingStudio::WebReader.read(url)
      end
    end
  end

  def test_userinfo_is_rejected_without_echoing_the_secret
    error = assert_raises(RecordingStudio::WebReader::UnsafeUrlError) do
      without_network { RecordingStudio::WebReader.read("https://user:s3cret@example.com/") }
    end

    refute_includes error.message, "s3cret"
  end

  def test_private_and_metadata_destinations_never_connect
    urls = %w[
      http://localhost/
      http://foo.localhost/admin
      http://metadata.google.internal/computeMetadata/v1/
      http://127.0.0.1/
      http://10.1.2.3/secret
      http://192.168.1.9/
      http://172.16.0.4/
      http://169.254.169.254/latest/meta-data/
      http://0.0.0.0/
      http://100.64.0.1/
      http://192.0.2.1/
      http://198.51.100.8/
      http://203.0.113.4/
      http://224.0.0.1/
      http://2130706433/
      http://[::1]/
      http://[fd00::1]/
    ]

    urls.each do |url|
      without_network do
        assert_raises(RecordingStudio::WebReader::UnsafeUrlError, url) do
          RecordingStudio::WebReader.read(url)
        end
      end
    end
  end

  def test_dns_answers_that_include_a_private_address_are_rejected
    called = false
    Net::HTTP.stub(:new, ->(*) { called = true }) do
      Resolv.stub(:getaddresses, ["93.184.216.34", "127.0.0.1"]) do
        assert_raises(RecordingStudio::WebReader::UnsafeUrlError) do
          RecordingStudio::WebReader.read("https://example.com/")
        end
      end
    end

    refute called
  end

  def test_empty_dns_is_a_fetch_error
    Resolv.stub(:getaddresses, []) do
      assert_raises(RecordingStudio::WebReader::FetchError) do
        RecordingStudio::WebReader.read("https://example.com/")
      end
    end
  end

  def test_redirect_to_a_private_address_is_rejected
    called = 0
    client = Client.new([redirect_response("http://169.254.169.254/latest/meta-data/")], [])
    Net::HTTP.stub(:new, lambda { |*|
      called += 1
      client
    }) do
      Resolv.stub(:getaddresses, ["93.184.216.34"]) do
        error = assert_raises(RecordingStudio::WebReader::UnsafeUrlError) do
          RecordingStudio::WebReader.read("https://example.com/start")
        end
        refute_includes error.message, "meta-data"
      end
    end

    assert_equal 1, called
  end

  def test_redirect_to_an_unsupported_scheme_is_invalid
    assert_raises(RecordingStudio::WebReader::InvalidUrlError) do
      read_page("https://example.com/start", [redirect_response("file:///etc/passwd")])
    end
  end

  def test_image_probe_reads_a_png_header_and_follows_redirects
    png = png_bytes(2400, 1600)
    result = nil
    log = with_network([redirect_response("/final.png"),
                        Response.new(code: 200, headers: { "content-type" => "image/png" }, body: png)]) do
      result = RecordingStudio::WebReader.probe_image("https://cdn.example.com/photo.png")
    end

    assert_equal "https://cdn.example.com/final.png", result[:url]
    assert_equal 2400, result[:width]
    assert_equal 1600, result[:height]
    assert_equal 1.5, result[:aspect_ratio]
    assert_equal :image_probe, result[:dimension_source]
    assert_equal "bytes=0-65535", log.last[:range]
    assert_equal 2, log.length
  end

  def test_image_header_reads_gif_jpeg_and_webp
    gif = "GIF89a".b + [32, 16].pack("vv")
    jpeg = "\xFF\xD8\xFF\xC0".b + [11, 8, 900, 1600].pack("nCnn") + "\x01\x11\x00".b
    webp = ("RIFF".b + "\x00\x00\x00\x00".b + "WEBP".b + "VP8X".b + ("\x00".b * 18))
    webp.setbyte(24, 1199 & 0xFF)
    webp.setbyte(25, (1199 >> 8) & 0xFF)
    webp.setbyte(26, (1199 >> 16) & 0xFF)
    webp.setbyte(27, 799 & 0xFF)
    webp.setbyte(28, (799 >> 8) & 0xFF)
    webp.setbyte(29, (799 >> 16) & 0xFF)

    assert_equal [32, 16], RecordingStudio::WebReader::ImageHeader.dimensions(gif)
    assert_equal [1600, 900], RecordingStudio::WebReader::ImageHeader.dimensions(jpeg)
    assert_equal [1200, 800], RecordingStudio::WebReader::ImageHeader.dimensions(webp)
    assert_nil RecordingStudio::WebReader::ImageHeader.dimensions("not an image")
  end

  def test_probe_of_a_non_image_does_not_raise
    result = nil
    with_network([Response.new(code: 404, headers: { "content-type" => "text/html" }, body: "<html>missing</html>")]) do
      result = RecordingStudio::WebReader.probe_image("https://example.com/missing.png")
    end

    assert_nil result[:width]
    assert_nil result[:dimension_source]
  end

  def test_reading_a_page_does_not_download_its_images
    page, log = read_page("https://example.com/article", [html_response(ARTICLE_HTML)])

    assert_equal 1, log.length
    assert(page.images.any? { |image| image[:width].nil? })
  end

  def test_probe_images_fills_missing_dimensions_and_keeps_the_original_page
    html = <<~HTML
      <!doctype html><html><body>
        <img src="https://cdn.example.com/known.jpg" alt="Known" width="10" height="10">
        <img src="https://cdn.example.com/photo.png" alt="Probed">
        <img src="http://127.0.0.1/secret.png" alt="Blocked">
      </body></html>
    HTML
    page, = read_page("https://example.com/article", [html_response(html)])
    probed = nil
    log = with_network([Response.new(code: 200, headers: { "content-type" => "image/png" },
                                     body: png_bytes(80, 40))]) do
      probed = RecordingStudio::WebReader.probe_images(page)
    end

    assert_equal 1, log.length
    assert_nil page.images[1][:width]
    known = probed.images.find { |image| image[:alt] == "Known" }
    photo = probed.images.find { |image| image[:alt] == "Probed" }
    blocked = probed.images.find { |image| image[:alt] == "Blocked" }
    assert_equal :html_attribute, known[:dimension_source]
    assert_equal 80, photo[:width]
    assert_equal 40, photo[:height]
    assert_equal 2.0, photo[:aspect_ratio]
    assert_equal :image_probe, photo[:dimension_source]
    assert_nil blocked[:width]
  end

  def test_probe_images_stops_after_ten_fetches_and_reuses_a_url
    images = Array.new(11) { |index| bare_image("https://cdn.example.com/#{index}.png") }
    images << bare_image("https://cdn.example.com/0.png")
    page = sample_page(images: images)
    calls = 0
    RecordingStudio::WebReader.stub(:probe_image, lambda { |url|
      calls += 1
      { url: url, width: 4, height: 2, aspect_ratio: 2.0, dimension_source: :image_probe }
    }) do
      probed = RecordingStudio::WebReader.probe_images(page)

      assert_equal RecordingStudio::WebReader::PROBE_IMAGE_LIMIT, calls
      assert_nil probed.images[10][:width]
      assert_equal 4, probed.images.last[:width]
    end
  end

  def test_explicit_cache_stores_observations_and_still_checks_dns
    cache = KeywordCache.new
    html = "<!doctype html><html><title>Cached</title><body><p>Cached body</p></body></html>"
    calls = 0
    client = Client.new([html_response(html)], [])
    addresses = [["93.184.216.34"], ["93.184.216.34"], ["93.184.216.34"]]
    Resolv.stub(:getaddresses, ->(*) { addresses.shift }) do
      Net::HTTP.stub(:new, lambda { |*|
        calls += 1
        client
      }) do
        first = RecordingStudio::WebReader.read("https://example.com/a", cache: cache, cache_ttl: 12)
        second = RecordingStudio::WebReader.read("https://example.com/a", cache: cache, cache_ttl: 12)

        assert_equal "Cached", first.title
        assert_equal "Cached", second.title
        assert_equal 1, calls
        assert_equal ["recording_studio_web_reader/v1/http/https://example.com/a", 12], cache.calls.first
      end
    end

    Resolv.stub(:getaddresses, ["10.9.8.7"]) do
      assert_raises(RecordingStudio::WebReader::UnsafeUrlError) do
        RecordingStudio::WebReader.read("https://example.com/a", cache: cache)
      end
    end
  end

  def test_positional_and_bare_caches_are_accepted
    positional = PositionalCache.new
    bare = BareCache.new
    html = "<!doctype html><html><title>Stored</title><body><p>Stored</p></body></html>"

    read_page("https://example.com/a", [html_response(html)], cache: positional)
    assert_equal({ expires_in: 300 }, positional.options)

    read_page("https://example.com/b", [html_response(html)], cache: bare)
    assert_equal "Stored", RecordingStudio::WebReader::Page.from_h(bare.store.values.first).title

    Resolv.stub(:getaddresses, ["93.184.216.34"]) do
      Net::HTTP.stub(:new, ->(*) { flunk "HTTP ran" }) do
        assert_raises(RecordingStudio::WebReader::ConfigurationError) do
          RecordingStudio::WebReader.read("https://example.com/", cache: Object.new)
        end
      end
    end
  end

  def test_a_not_found_page_can_be_cached
    cache = KeywordCache.new
    html = "<!doctype html><html><title>Missing</title><body><p>Missing page</p></body></html>"
    page, = read_page("https://example.com/missing", [html_response(html, status: 404)], cache: cache)

    assert_equal 404, page.status
    assert_equal 404, cache.store.values.first["status"]
  end

  def test_browser_fetcher_can_replace_http_without_changing_read
    RecordingStudio::WebReader.register_fetcher(:browser, lambda { |hop|
      assert_equal "93.184.216.34", hop[:address]
      {
        status: 200,
        headers: { "content-type" => "text/html" },
        body: "<!doctype html><html><title>Rendered</title><body><article>" \
              "<p>From the browser</p></article></body></html>",
        content_type: "text/html",
        location: nil,
        address: hop[:address]
      }
    }, override: true)
    page = nil
    Net::HTTP.stub(:new, ->(*) { flunk "HTTP fetcher ran" }) do
      Resolv.stub(:getaddresses, ["93.184.216.34"]) do
        page = RecordingStudio::WebReader.read("https://example.com/app", strategy: :browser)
      end
    end

    assert_equal "Rendered", page.title
    assert_equal "From the browser", page.text
  end

  def test_a_fetcher_that_reports_another_address_is_refused
    RecordingStudio::WebReader.register_fetcher(:browser, lambda { |hop|
      {
        status: 200,
        headers: { "content-type" => "text/html" },
        body: "<html><title>Wrong</title></html>",
        content_type: "text/html",
        location: nil,
        address: "8.8.8.8",
        pinned: hop[:address]
      }
    }, override: true)

    Resolv.stub(:getaddresses, ["93.184.216.34"]) do
      error = assert_raises(RecordingStudio::WebReader::UnsafeUrlError) do
        RecordingStudio::WebReader.read("https://example.com/app", strategy: :browser)
      end
      assert_equal "The URL is not allowed", error.message
    end
  end

  def test_unknown_fetch_strategy_is_a_configuration_error
    Resolv.stub(:getaddresses, ["93.184.216.34"]) do
      assert_raises(RecordingStudio::WebReader::ConfigurationError) do
        RecordingStudio::WebReader.read("https://example.com/", strategy: :missing)
      end
    end
  end

  def test_extractor_and_analysis_registry
    page, = read_page("https://example.com/article", [html_response(ARTICLE_HTML)])
    RecordingStudio::WebReader.register_extractor(:article_metadata, lambda { |extracted|
      { title: extracted.title, author: extracted.metadata.article["author"] }
    })
    RecordingStudio::WebReader.register_extractor(:title_only, &:title)
    RecordingStudio::WebReader.register_analysis(:paywall, lambda { |extracted, model: "local"|
      {
        value: extracted.text.to_s.length < 400 ? :hard_paywall : :open,
        confidence: 0.96,
        reason: model,
        evidence: [{ source: :text, path: "text.length", value: extracted.text.to_s.length }]
      }
    })
    RecordingStudio::WebReader.register_analysis(:paywall, lambda { |*|
      { value: :open, confidence: 0.2, reason: "other", evidence: [] }
    }, namespace: :acme)

    extracted = page.extract(:article_metadata)
    assert_equal "Example Article", extracted[:title]
    assert_equal "Ada Lovelace", extracted[:author]
    assert_equal "Example Article", page.extract(:title_only)

    result = page.analyze(:paywall, model: "jev-test")
    assert_instance_of RecordingStudio::WebReader::AnalysisResult, result
    assert_equal :hard_paywall, result.value
    assert_equal 0.96, result.confidence
    assert_equal "jev-test", result.reason
    assert_equal :text, result.evidence.first.source
    assert_equal "text.length", result.evidence.first.path
    assert_equal page.text.length, result.evidence.first.value
    JSON.generate(result.to_h)

    other = page.analyze(:paywall, namespace: :acme)
    assert_equal :open, other.value

    assert_raises(RecordingStudio::WebReader::RegistryError) do
      RecordingStudio::WebReader.register_analysis(:paywall, ->(*) { { value: :open } })
    end
    RecordingStudio::WebReader.register_analysis(:paywall, lambda { |*|
      { value: :blocked, confidence: 1, reason: "override", evidence: [] }
    }, override: true)
    assert_equal :blocked, page.analyze(:paywall).value

    assert_raises(RecordingStudio::WebReader::RegistryError) { page.analyze(:missing) }
    assert_raises(RecordingStudio::WebReader::RegistryError) do
      RecordingStudio::WebReader.register_analysis(:bad, ->(*) { "nope" })
      page.analyze(:bad)
    end

    names = RecordingStudio::WebReader.extensions
    assert(names.any? { |row| row[:kind] == :fetcher && row[:name] == :http })
    assert(names.any? do |row|
      row[:kind] == :extractor && row[:name] == :article_metadata && row[:namespace] == :recording_studio_web_reader
    end)
    assert(names.any? { |row| row[:kind] == :analysis && row[:namespace] == :acme && row[:name] == :paywall })

    RecordingStudio::WebReader.reset_extensions!
    assert_raises(RecordingStudio::WebReader::RegistryError) { page.extract(:article_metadata) }
    assert(RecordingStudio::WebReader.extensions.any? { |row| row[:kind] == :fetcher })
  end

  def test_duplicate_fetcher_registration_is_rejected
    assert_raises(RecordingStudio::WebReader::RegistryError) do
      RecordingStudio::WebReader.register_fetcher(:http, ->(*) { {} })
    end
  end

  def test_instrumentation_records_the_read_without_page_content
    payloads = []
    during = []
    subscription = ActiveSupport::Notifications.subscribe("read.recording_studio_web_reader") do |*, payload|
      during << payload.key?(:duration_ms)
      payloads << payload
    end
    headers = { "set-cookie" => "session=SECRET-COOKIE" }
    page, = read_page(
      "https://example.com/article?token=SECRET-QUERY",
      [html_response(ARTICLE_HTML, headers: headers)]
    )

    assert_equal "Example Article", page.title
    payload = payloads.fetch(0)
    refute during.fetch(0)
    assert_equal 1, payload[:schema_version]
    assert_equal :read, payload[:operation]
    assert_equal :http, payload[:strategy]
    assert_equal "example.com", payload[:host]
    assert_equal true, payload[:success]
    assert_equal 200, payload[:status]
    assert_equal "text/html", payload[:content_type]
    assert_equal 0, payload[:redirect_count]
    assert_equal 1, payload[:request_count]
    assert payload[:bytes].positive?
    assert_nil payload[:error_type]
    assert_equal false, payload[:cached]
    assert_kind_of Integer, payload[:duration_ms]
    encoded = JSON.generate(payload)
    refute_includes encoded, "SECRET-QUERY"
    refute_includes encoded, "SECRET-COOKIE"
    refute_includes encoded, "Main paragraph"
    refute_includes encoded, "SECRET-NAV"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  def test_instrumentation_records_failures_and_can_be_disabled
    failure = []
    subscription = ActiveSupport::Notifications.subscribe("read.recording_studio_web_reader") do |*, payload|
      failure << payload
    end
    assert_raises(RecordingStudio::WebReader::UnsafeUrlError) do
      without_network { RecordingStudio::WebReader.read("http://127.0.0.1/") }
    end
    assert_equal false, failure.fetch(0)[:success]
    assert_equal "RecordingStudio::WebReader::UnsafeUrlError", failure.fetch(0)[:error_type]
    assert_equal 0, failure.fetch(0)[:request_count]
    assert_kind_of Integer, failure.fetch(0)[:duration_ms]

    RecordingStudio::WebReader.configuration.instrumentation_enabled = false
    before = failure.length
    read_page("https://example.com/",
              [html_response("<!doctype html><html><title>Quiet</title><body><p>Quiet</p></body></html>")])
    assert_equal before, failure.length
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  def test_probe_instrumentation_uses_its_own_event
    payloads = []
    subscription = ActiveSupport::Notifications.subscribe("probe_image.recording_studio_web_reader") do |*, payload|
      payloads << payload
    end
    with_network([Response.new(code: 200, headers: { "content-type" => "image/png" }, body: png_bytes(8, 4))]) do
      RecordingStudio::WebReader.probe_image("https://cdn.example.com/a.png")
    end

    payload = payloads.fetch(0)
    assert_equal :probe_image, payload[:operation]
    assert_equal true, payload[:success]
    assert_equal "image/png", payload[:content_type]
    assert_equal "cdn.example.com", payload[:host]
    refute_includes JSON.generate(payload), "PNG"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  def test_ai_tool_registration_is_optional_and_truncates_the_page
    remove_ai = false
    assert_nil RecordingStudio::WebReader::AiTool.register! unless defined?(::RecordingStudioAI)

    page = RecordingStudio::WebReader::Page.new(
      url: "https://example.com/a",
      final_url: "https://example.com/a",
      status: 200,
      headers: {},
      content_type: "text/html",
      title: "Tool",
      description: nil,
      canonical_url: nil,
      text: "x" * 9_000,
      html: "<html>SECRET-HTML</html>",
      metadata: RecordingStudio::WebReader::Page::Metadata.new(open_graph: {}, twitter: {}, json_ld: [], article: {},
                                                               meta: {}),
      links: Array.new(30) { |index| { url: "https://example.com/#{index}", text: index.to_s, rel: [] } },
      images: Array.new(20) do |index|
        { url: "https://example.com/#{index}.jpg", alt: "", width: nil, height: nil, aspect_ratio: nil,
          source: :html_attribute, dimension_source: nil, variants: [] }
      end,
      challenge: nil
    )
    projected = RecordingStudio::WebReader::AiTool.project(page)
    refute projected.key?("html")
    assert_nil projected["challenge"]
    assert_equal "summary", projected["content"]
    assert_equal true, projected["text_truncated"]
    assert_equal 8_000, projected["text"].length
    assert_equal 30, projected["link_count"]
    assert_equal 25, projected["links"].length
    assert_equal 20, projected["image_count"]
    assert_equal 15, projected["images"].length
    refute_includes JSON.generate(projected), "SECRET-HTML"

    full = RecordingStudio::WebReader::AiTool.project(page, content: "full")
    assert_equal "full", full["content"]
    assert_equal false, full["text_truncated"]
    assert_equal 9_000, full["text"].length
    assert_equal 30, full["links"].length
    assert_equal 20, full["images"].length
    refute full.key?("html")
    refute_includes JSON.generate(full), "SECRET-HTML"

    fitted = RecordingStudio::WebReader::AiTool.project(page.with(text: "y" * 250_000), content: "full")
    assert_equal true, fitted["text_truncated"]
    assert_operator JSON.generate(fitted).bytesize, :<=, RecordingStudio::WebReader::AiTool::RESULT_BYTE_BUDGET

    bulky = page.with(
      text: "The article stays.",
      metadata: RecordingStudio::WebReader::Page::Metadata.new(
        open_graph: {}, twitter: {}, article: {}, meta: {},
        json_ld: [{ "blob" => "z" * 250_000 }]
      )
    )
    trimmed = RecordingStudio::WebReader::AiTool.project(bulky)
    assert_equal "The article stays.", trimmed["text"]
    assert_equal [], trimmed.dig("metadata", "json_ld")
    assert_operator JSON.generate(trimmed).bytesize, :<=, RecordingStudio::WebReader::AiTool::RESULT_BYTE_BUDGET

    tools = ToolRegistry.new
    unless defined?(::RecordingStudioAI)
      Object.const_set(:RecordingStudioAI, Module.new)
      remove_ai = true
    end
    RecordingStudioAI.define_singleton_method(:tools) { tools }
    RecordingStudio::WebReader::AiTool.register!
    assert_equal :visit_web_page, tools.kwargs[:key]
    assert_equal 2, tools.kwargs[:version]
    content = tools.kwargs[:parameters].find { |parameter| parameter[:name] == :content }
    assert_equal "summary", content[:default]
    assert_equal %w[summary full], content[:allowed_values]
    assert_equal true, tools.kwargs[:override]
    assert_equal true, tools.kwargs[:read_only]
    assert_equal true, tools.kwargs[:idempotent]
    assert_equal false, tools.kwargs[:destructive]

    RecordingStudio::WebReader.stub(:read, page) do
      result = tools.kwargs[:executor].call({ "url" => "https://example.com/a" }, {})
      refute result.key?("html")
      assert_equal "Tool", result["title"]
    end
  ensure
    Object.send(:remove_const, :RecordingStudioAI) if remove_ai
  end

  def test_gem_does_not_depend_on_recording_studio_ai_or_call_decide
    gemspec = File.read(File.expand_path("../recording_studio_web_reader.gemspec", __dir__))
    refute_includes gemspec, "recording_studio_ai"

    Dir[File.expand_path("../lib/recording_studio_web_reader.rb", __dir__),
        File.expand_path("../lib/recording_studio_web_reader/**/*.rb", __dir__)].each do |path|
      source = File.read(path)
      refute_includes source, "require \"recording_studio_ai\""
      refute_includes source, ".decide"
    end
  end

  private

  def bare_image(url)
    { url: url, alt: "", width: nil, height: nil, aspect_ratio: nil, source: :html_attribute,
      dimension_source: nil, variants: [] }
  end

  def sample_page(images:)
    RecordingStudio::WebReader::Page.new(
      url: "https://example.com/a",
      final_url: "https://example.com/a",
      status: 200,
      headers: {},
      content_type: "text/html",
      title: "Probe",
      description: nil,
      canonical_url: nil,
      text: "Hello",
      html: "<html></html>",
      metadata: RecordingStudio::WebReader::Page::Metadata.new(
        open_graph: {}, twitter: {}, json_ld: [], article: {}, meta: {}
      ),
      links: [],
      images: images,
      challenge: nil
    )
  end

  def evidence_value(page, path)
    page.challenge.evidence.find { |item| item.path == path }&.value
  end

  def without_network(&block)
    Resolv.stub(:getaddresses, ->(*) { flunk "DNS ran" }) do
      Net::HTTP.stub(:new, ->(*) { flunk "HTTP ran" }, &block)
    end
  end

  class KeywordCache
    attr_reader :calls, :store

    def initialize
      @calls = []
      @store = {}
    end

    def fetch(key, expires_in: nil)
      @calls << [key, expires_in]
      @store[key] ||= yield
    end
  end

  class PositionalCache
    attr_reader :options, :store

    def initialize
      @store = {}
    end

    def fetch(key, options = nil)
      @options = options
      @store[key] ||= yield
    end
  end

  class BareCache
    attr_reader :store

    def initialize
      @store = {}
    end

    def fetch(key)
      @store[key] ||= yield
    end
  end

  class ToolRegistry
    attr_reader :kwargs

    def register(**kwargs)
      @kwargs = kwargs
    end
  end
end
