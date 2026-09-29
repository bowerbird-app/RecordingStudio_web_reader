# frozen_string_literal: true

require "test_helper"
require_relative "support/web_reader_http"

class EmbeddedVideoPageTest < Minitest::Test
  include WebReaderHttp

  WATCH = "https://www.youtube.com/watch?v=cU2RuIqTI8U"
  TITLE = "339: Success Lessons I Learned Building Bowerbird with Nic Granleese"
  GENERIC = "Enjoy the videos and music you love, upload original content, and share it all with friends, " \
            "family, and the world on YouTube."
  DESCRIPTION = "Nic Granleese is a self-proclaimed \"recovering architect\" who is now the CEO of Bowerbird."
  FOOTER = "About Press Copyright Privacy NFL Sunday Ticket"

  def setup
    @original_configuration = RecordingStudio::WebReader.instance_variable_get(:@configuration)
    RecordingStudio::WebReader.instance_variable_set(
      :@configuration,
      RecordingStudio::WebReader::Configuration.new
    )
    restore_fetchers
  end

  def teardown
    restore_fetchers
    RecordingStudio::WebReader.instance_variable_set(:@configuration, @original_configuration)
  end

  def restore_fetchers
    RecordingStudio::WebReader.register_fetcher(:http, RecordingStudio::WebReader::Http, override: true)
    RecordingStudio::WebReader.register_fetcher(:browser, RecordingStudio::WebReader::Browser, override: true)
  end

  def test_player_response_fills_title_description_and_text
    page = read_watch(player_script("videoDetails" => {
                                      "title" => TITLE,
                                      "shortDescription" => "Nic Granleese is the CEO of Bowerbird.\nA second line."
                                    }))

    assert_equal TITLE, page.title
    assert_equal "Nic Granleese is the CEO of Bowerbird. A second line.", page.description
    refute_includes page.description, "Enjoy the videos and music you love"
    assert_nil page.canonical_url
    assert_nil page.challenge
    assert_operator page.text.index(TITLE), :<, page.text.index("NFL Sunday Ticket")
    assert_operator page.text.index("CEO of Bowerbird"), :<, page.text.index("NFL Sunday Ticket")
    assert_includes page.text[0, 8000], TITLE
    assert_includes page.text[0, 8000], "CEO of Bowerbird"
    refute_includes page.text, "shortDescription"
    assert_equal "https://www.youtube.com/undefined", page.links.find { |link| link[:text] == "Undefined link" }[:url]
    assert_equal %w[url final_url status headers content_type title description canonical_url text html metadata
                    links images challenge], page.to_h.keys
  end

  def test_watch_page_json_uses_the_renderer_title_and_attributed_description
    page = read_watch(data_script(
                        "videoDetails" => {
                          "title" => { "simpleText" => "not a string title" },
                          "playerOverlayVideoDetailsRenderer" => {
                            "title" => { "simpleText" => "overlay inside videoDetails" }
                          }
                        },
                        "videoPrimaryInfoRenderer" => { "title" => { "runs" => [{ "text" => TITLE }] } },
                        "attributedDescription" => { "content" => "Promo line.\n\n#{DESCRIPTION}" },
                        "playerOverlayVideoDetailsRenderer" => { "title" => { "simpleText" => TITLE } }
                      ))

    assert_equal TITLE, page.title
    assert_includes page.description, "CEO of Bowerbird"
    refute_includes page.description, GENERIC
    assert_nil page.canonical_url
    assert_nil page.challenge
    assert_operator page.text.index(TITLE), :<, page.text.index(FOOTER)
    refute_includes page.text, "playabilityStatus"
  end

  def test_classic_player_fields_win_over_renderer_fields
    page = read_watch(player_script(
                        "attributedDescription" => { "content" => "Attributed description" },
                        "videoPrimaryInfoRenderer" => { "title" => { "runs" => [{ "text" => "Primary title" }] } },
                        "playerOverlayVideoDetailsRenderer" => { "title" => { "simpleText" => "Overlay title" } },
                        "videoDetails" => {
                          "title" => "Classic title Building Bowerbird",
                          "shortDescription" => "Classic short description mentions Bowerbird"
                        }
                      ))

    assert_equal "Classic title Building Bowerbird", page.title
    assert_equal "Classic short description mentions Bowerbird", page.description
  end

  def test_overlay_title_is_used_when_no_string_title_is_present
    page = read_watch(data_script(
                        "playerOverlayVideoDetailsRenderer" => {
                          "title" => { "simpleText" => "Overlay Building Bowerbird" }
                        }
                      ))

    assert_equal "Overlay Building Bowerbird", page.title
    assert_equal GENERIC, page.description
  end

  def test_document_title_is_kept_when_it_already_includes_the_embedded_title
    html = watch_html(
      player_script("videoDetails" => { "title" => TITLE, "shortDescription" => DESCRIPTION }),
      title: "#{TITLE} - YouTube"
    )
    page = read_html(html)

    assert_equal "#{TITLE} - YouTube", page.title
    assert_equal DESCRIPTION, page.description
  end

  def test_visible_text_is_not_repeated_when_it_already_includes_the_player_words
    description = "CEO of Bowerbird in the article."
    html = watch_html(
      player_script("videoDetails" => { "title" => TITLE, "shortDescription" => description }),
      body: "<article><p>#{TITLE}. #{description}</p></article><footer>Footer legal</footer>"
    )
    page = read_html(html)

    assert_equal "#{TITLE}. #{description}", page.text
    refute_includes page.text, "Footer legal"
  end

  def test_description_keeps_escapes_braces_and_unicode
    html = watch_html(player_script(
                        "videoDetails" => {
                          "title" => TITLE,
                          "shortDescription" => "Café CEO of Bowerbird } still here"
                        }
                      ))
    page = read_html("café #{html}")

    assert_equal "Café CEO of Bowerbird } still here", page.description
    assert_includes page.text, "Café CEO of Bowerbird } still here"
  end

  def test_a_marker_that_is_not_an_assignment_does_not_hide_a_later_player_object
    payload = JSON.generate("videoPrimaryInfoRenderer" => { "title" => { "runs" => [{ "text" => TITLE }] } })
    script = <<~SCRIPT
      <script>window['ytInitialPlayerResponse'];</script>
      <script>var ytInitialData = #{payload};</script>
    SCRIPT
    page = read_watch(script)

    assert_equal TITLE, page.title
  end

  def test_invalid_player_json_leaves_the_document_fields_alone
    script = '<script>var ytInitialPlayerResponse = {"videoDetails": {"title": "Building Bowerbird",}};</script>'
    page = read_watch(script)

    assert_equal "- YouTube", page.title
    assert_equal GENERIC, page.description
    assert_nil page.challenge
  end

  def test_broken_player_json_leaves_the_document_fields_alone
    script = '<script>var ytInitialPlayerResponse = {"videoDetails": {"title": "Building Bowerbird"'
    page = read_watch(script)

    assert_equal "- YouTube", page.title
    assert_equal GENERIC, page.description
    assert_includes page.text, FOOTER
    assert_nil page.challenge
  end

  def test_real_canonical_url_is_kept
    html = watch_html(
      player_script("videoDetails" => { "title" => TITLE, "shortDescription" => DESCRIPTION }),
      canonical: WATCH
    )
    page = read_html(html)

    assert_equal WATCH, page.canonical_url
  end

  def test_relative_canonical_hrefs_still_resolve
    base = "https://example.com/videos/watch"
    {
      "/canonical" => "https://example.com/canonical",
      "?v=1" => URI.join(base, "?v=1").to_s,
      "./other" => URI.join(base, "./other").to_s,
      "../other" => URI.join(base, "../other").to_s,
      "https://example.com/absolute" => "https://example.com/absolute"
    }.each do |href, expected|
      html = "<html><head><link rel=\"canonical\" href=\"#{href}\"></head><body><p>Hi</p></body></html>"
      page = read_html(html, base)
      assert_equal expected, page.canonical_url, href
    end
  end

  def test_canonical_href_that_is_not_a_url_stays_nil
    ["undefined", " undefined ", "javascript:alert(1)", "watch", ""].each do |href|
      html = "<html><head><title>Example Article</title>" \
             "<meta name=\"description\" content=\"A short description\">" \
             "<link rel=\"canonical\" href=\"#{href}\"></head>" \
             "<body><article><p>Main paragraph.</p></article></body></html>"
      page = read_html(html, "https://example.com/article")

      assert_equal "Example Article", page.title, href
      assert_equal "A short description", page.description, href
      assert_equal "Main paragraph.", page.text, href
      assert_nil page.canonical_url, href
      assert_nil page.challenge, href
    end
  end

  def test_player_json_does_not_change_interstitial_evidence
    payload = JSON.generate("videoDetails" => { "title" => TITLE, "shortDescription" => DESCRIPTION })
    html = <<~HTML
      <html>
        <head><title>Just a moment...</title></head>
        <body>
          <div role="main"><noscript>Enable JavaScript and cookies to continue</noscript></div>
          <script src="/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1"></script>
          <script>var ytInitialPlayerResponse = #{payload};</script>
        </body>
      </html>
    HTML
    page = read_html(html, "https://example.com/challenge", status: 403)
    title = page.challenge.evidence.find { |item| item.path == "title" }

    assert_equal :javascript, page.challenge.kind
    assert_equal "Just a moment...", title.value
    assert_equal TITLE, page.title
  end

  private

  def read_watch(script, **)
    read_html(watch_html(script, **))
  end

  def read_html(html, url = WATCH, status: 200)
    page, = read_page(url, [html_response(html, status: status)])
    page
  end

  def watch_html(script, title: "- YouTube", canonical: "undefined", description: GENERIC, body: nil)
    content = body || "<div>#{FOOTER}</div><a href=\"undefined\">Undefined link</a>"
    <<~HTML
      <!doctype html>
      <html>
        <head>
          <title>#{title}</title>
          <meta name="description" content="#{description}">
          <link rel="canonical" href="#{canonical}">
        </head>
        <body>
          #{content}
          #{script}
        </body>
      </html>
    HTML
  end

  def player_script(payload)
    "<script>var ytInitialPlayerResponse = #{JSON.generate(payload)};</script>"
  end

  def data_script(payload)
    player = JSON.generate("responseContext" => {}, "playabilityStatus" => { "status" => "OK" })
    "<script>var ytInitialPlayerResponse = #{player};</script>" \
      "<script>var ytInitialData = #{JSON.generate(payload)};</script>"
  end
end
