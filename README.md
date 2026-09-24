# Recording Studio Web Reader

`RecordingStudio::WebReader` fetches one public page and returns a normalized observation of that page.

Web Search discovers URLs. Web Reader visits a URL and records what is there. Another gem interprets that observation for its own domain. Recording Studio AI can classify an observation later. Web Reader does not require it, and it does not decide whether a page is press coverage, a journalist, or a Featured In item.

## Architecture

```text
Web Search
    discovers URLs

Web Reader
    fetches and normalizes one page

Extractors and analyses
    registered by Web Reader or by another gem

Recording Studio AI
    optional tools and decisions

Featured In and other products
    domain rules
```

`RecordingStudio::WebReader.read` is the public call. A private reader owns redirects, response limits, SSRF checks, and instrumentation. A fetcher performs one HTTP hop and connects to an address the reader already approved. A later browser fetcher can register beside HTTP. Callers still use `read`.

The page object hides the HTTP client and the HTML parser. Links, images, and metadata are plain Ruby values. `to_h` uses string keys so `JSON.generate(page.to_h)` works.

## Install

Add the gem to the host app and install it.

```ruby
gem "recording_studio_web_reader", github: "bowerbird-app/RecordingStudio_web_reader"
```

```bash
bundle install
bin/rails generate recording_studio_web_reader:install
bin/rails generate recording_studio_web_reader:migrations
```

The install generator mounts `RecordingStudio::WebReader::Engine` and copies an initializer. This version has no database tables. The migrations generator reports that and copies nothing.

## Configure

Set defaults in `config/initializers/recording_studio_web_reader.rb`.

```ruby
RecordingStudio::WebReader.configure do |config|
  config.user_agent = "MyApp WebReader"
  config.open_timeout = 5
  config.read_timeout = 10
  config.write_timeout = 5
  config.max_redirects = 5
  config.max_response_bytes = 2_000_000
  config.fetch_strategy = :http
  config.instrumentation_enabled = true
end
```

`nil` restores the default for each timeout, the redirect limit, the response limit, the strategy, and instrumentation. Instrumentation stays on unless you set it to `false`.

The default user agent is `RecordingStudioWebReader/` plus the gem version. The default strategy is `:http`. TLS verification stays on. There is no global page cache.

## Read a page

```ruby
page = RecordingStudio::WebReader.read("https://example.com/article")
```

Pass `strategy:` to use a registered fetcher for that call. The default is `config.fetch_strategy`.

HTTP 403, 404, and 500 are pages. A timeout, an unsafe URL, a non-HTML body, or a response over the size limit raises `RecordingStudio::WebReader::Error`. The message does not include the response body, cookies, or authorization headers.

## Page

| Reader | Meaning |
| --- | --- |
| `page.url` | URL you passed in |
| `page.final_url` | URL after redirects, without a fragment |
| `page.status` | HTTP status |
| `page.headers` | Response headers, without cookie or authorization fields |
| `page.content_type` | Media type, without parameters |
| `page.title` | Document title |
| `page.description` | Meta description, or `og:description` when the meta description is missing |
| `page.canonical_url` | Absolute canonical URL when it is HTTP or HTTPS |
| `page.text` | Main text |
| `page.html` | Raw response body |
| `page.metadata` | Structured metadata |
| `page.links` | Absolute HTTP and HTTPS links |
| `page.images` | Discovered images |
| `page.to_h` | JSON-safe hash with string keys |

`page.text` drops `script`, `style`, `nav`, `footer`, `header`, `aside`, and `form`, then prefers `article`, `main`, or `[role=main]`. The raw HTML stays on `page.html`. Extraction does not call a language model. It is a deterministic selection in Nokogiri, not a full readability port. One HTML parser keeps the gem small enough for other Recording Studio gems to depend on.

## Metadata

`page.metadata` keeps the standard blocks as data. It does not promote every meta tag to its own page attribute.

| Reader | Contents |
| --- | --- |
| `open_graph` | `og:*` properties, with the `og:` prefix removed |
| `twitter` | `twitter:*` names and properties |
| `json_ld` | Parsed JSON-LD objects. Invalid JSON is skipped |
| `article` | `article:*` properties, plus `author` from the author meta tag when present |
| `meta` | `meta name` values |

## Links

Each link is a hash with `url`, `text`, and `rel`. Relative URLs are resolved against `page.final_url`. `javascript:` and `mailto:` links are omitted. An HTTP link to a private address is still returned. It is an observation. Fetching it later goes through the same safety checks as `read`.

## Images

Each image is a hash.

```ruby
{
  url: "https://example.com/photo.jpg",
  alt: "Photo",
  width: 1600,
  height: 900,
  aspect_ratio: 1.778,
  source: :html_attribute,
  dimension_source: :html_attribute,
  variants: [
    { url: "https://example.com/photo-640.jpg", width_hint: 640 },
    { url: "https://example.com/photo-1200.jpg", width_hint: 1200 }
  ]
}
```

`source` says where the URL came from. `:html_attribute`, `:lazy_attribute`, `:srcset`, `:open_graph`, and `:twitter` are the current values. Lazy attributes are `data-src`, `data-lazy-src`, and `data-original`. `srcset` and `data-srcset` fill `variants`. A `640w` descriptor sets `width_hint`. A `2x` descriptor leaves `width_hint` nil.

`dimension_source` is `:html_attribute` only when both width and height are positive integers on the element or on `og:image:width` and `og:image:height`. A percentage is ignored. `read` does not download images.

## Probe image dimensions

Probe a URL when a caller needs intrinsic dimensions.

```ruby
RecordingStudio::WebReader.probe_image("https://cdn.example.com/photo.png")
# => { url:, width: 2400, height: 1600, aspect_ratio: 1.5, dimension_source: :image_probe }
```

Enrich a page without changing the original page.

```ruby
enriched = RecordingStudio::WebReader.probe_images(page)
```

Images that already have both dimensions are left alone. One URL is fetched once. A failed probe leaves that image unchanged. The probe uses the HTTP fetcher, sends a byte range, and reads at most 64 KiB. PNG, GIF, JPEG, and WebP headers supply the size when the bytes are enough. The result uses `:image_probe`. An unrecognized body returns nil dimensions and does not raise.

## Register an extractor

An extractor derives data from a page. It does not have to score confidence.

```ruby
RecordingStudio::WebReader.register_extractor(:article_metadata, MyGem::ArticleMetadata)

page.extract(:article_metadata)
# => { title: "...", author: "..." }
```

The callable receives the page. Keyword arguments passed to `extract` are forwarded. Names live in a namespace. The default namespace is `:recording_studio_web_reader`. Pass `namespace:` to both `register_extractor` and `extract` when another gem needs its own name. Registering the same namespace and name twice raises `RegistryError`. Pass `override: true` to replace it. `RecordingStudio::WebReader.extensions` lists fetchers, extractors, and analyses. `reset_extensions!` clears extractors and analyses. It leaves fetchers in place.

## Register an analysis

An analysis classifies a page. Web Reader stores the result. It does not care whether the callable used Ruby, Jev, or another model.

```ruby
result = page.analyze(:paywall, root_recording: recording, initiator: user)

result.value
result.confidence
result.reason
result.evidence
```

A hash return is wrapped in `AnalysisResult`. Each evidence item becomes `Evidence` with `source`, `path`, and `value`. `result.to_h` is JSON-safe. Return `AnalysisResult` directly when you already built one.

## Paywall example

Put this in the gem that owns the decision, not in Web Reader.

```ruby
module Coverage
  class PaywallAnalysis
    def self.call(page, root_recording:, initiator:, **)
      observations = {
        "http_status" => page.status,
        "body_chars" => page.text.to_s.length
      }

      response = RecordingStudioAI.decide(
        state: observations.to_json,
        questions: {
          access: {
            type: :choice,
            instructions: "How is this page gated?",
            criteria: {
              open: "The article text is available",
              metered: "A meter allows some free articles",
              soft_paywall: "Some article text is visible and the rest asks for payment",
              hard_paywall: "The article text is withheld",
              login_required: "A login wall blocks the text",
              blocked: "The response is an error or interstitial",
              unknown: "The page does not show enough to classify"
            }
          }
        },
        purpose: "page_access",
        root_recording: root_recording,
        initiator: initiator
      )
      answer = response.answers[:access]

      {
        value: answer.choice,
        confidence: answer.confidence,
        reason: "Jev classified page access.",
        evidence: [
          { source: :http, path: "status", value: page.status },
          { source: :text, path: "text.length", value: page.text.to_s.length }
        ]
      }
    end
  end
end

RecordingStudio::WebReader.register_analysis(:paywall, Coverage::PaywallAnalysis)
```

`page.analyze(:paywall, root_recording: recording, initiator: user)` runs it. Web Reader does not call `decide` and does not depend on `recording_studio_ai`. If that gem is absent, register a Ruby callable instead.

The dummy app registers a local `:paywall` analysis that looks only at text length. That registration is dummy code. It is there to show the contract.

## Recording Studio AI

This gem does not depend on Recording Studio AI. When that gem is already loaded, the engine registers a `visit_web_page` tool. The tool calls `RecordingStudio::WebReader.read`. It does not open its own HTTP path.

The tool result omits raw HTML. Text is capped at 8,000 characters. Links are capped at 25 and images at 15. `text_truncated`, `link_count`, and `image_count` say what was left out. The Ruby page is still complete.

## Instrumentation

Subscribers receive `read.recording_studio_web_reader` and `probe_image.recording_studio_web_reader` through `ActiveSupport::Notifications`.

The payload has `schema_version`, `operation`, `strategy`, `host`, `success`, `status`, `content_type`, `redirect_count`, `bytes`, `request_count`, `error_type`, `cached`, and `duration_ms`. `duration_ms` is set on the payload after the notification block returns. `host` is the hostname only. The payload does not include the URL, HTML, page text, cookies, or authorization headers. Set `config.instrumentation_enabled = false` to skip the notification. `cached` is `false` on a network read. A cache hit does not emit a read event.

## Cache

Nothing is cached unless the caller passes `cache:`.

```ruby
RecordingStudio::WebReader.read(url, cache: Rails.cache, cache_ttl: 300)
```

The key is `recording_studio_web_reader/v1/` plus the strategy and the URL. The stored value is `page.to_h`. A hit still resolves DNS and rejects a host that now points at a private address. The caller owns freshness. `cache_ttl` is passed as `expires_in` when `fetch` accepts it. A 404 HTML page is stored because the fetch succeeded. A timeout is not stored.

## Security

Only `http` and `https` URLs are accepted. Userinfo is rejected. Redirects are checked again, including the scheme and the resolved address.

These destinations are rejected before a connection opens.

- `localhost`, names ending in `.localhost`, and `metadata.google.internal`
- Names ending in `.internal`
- Loopback, private, link-local, and shared address ranges
- Cloud metadata addresses such as `169.254.169.254`
- Documentation, CGNAT, multicast, and reserved ranges
- A DNS answer set that includes any blocked address
- Decimal hostnames such as `2130706433`

The HTTP fetcher connects to the approved address and uses the hostname for the Host header and TLS SNI. Certificate verification stays at `VERIFY_PEER`.

## Errors

| Error | When it is raised |
| --- | --- |
| `InvalidUrlError` | Blank URL, or a scheme other than HTTP or HTTPS |
| `UnsafeUrlError` | Private network, metadata host, or userinfo |
| `TimeoutError` | Open, read, or write timeout. This is a `FetchError` |
| `FetchError` | DNS failure, connection failure, or a redirect with no Location |
| `TooManyRedirectsError` | More redirects than `max_redirects` |
| `ResponseTooLargeError` | Declared or actual body over `max_response_bytes` |
| `UnsupportedContentTypeError` | Body is not HTML. `status` is available |
| `ConfigurationError` | Unknown fetch strategy, or a cache that has no `fetch` |
| `RegistryError` | Duplicate registration, unknown extension, or a bad analysis result |

## Fetch strategies

Register a fetcher when a page needs a browser later.

```ruby
RecordingStudio::WebReader.register_fetcher(:browser, MyGem::Browser)
RecordingStudio::WebReader.read(url, strategy: :browser)
```

The callable receives one hop. The hop includes `url`, `address`, `host`, `port`, `https`, timeouts, `max_bytes`, `user_agent`, and `on_overflow`. Return `status`, `headers`, `body`, `content_type`, and `location`. Do not follow redirects inside the fetcher. The reader does that, and it checks every target.

## Dummy app

The dummy app is a signed-in developer page. Enter a URL and inspect the final URL, status, title, description, text, metadata, links, images, dimensions, and variants. Check **Probe image dimensions** to run `probe_images`. The page also shows the dummy paywall analysis.

The dummy Gemfile pins Recording Studio `v4.2.0`, FlatPack `v0.1.177`, and Accessible `v0.9.1`. Sign in at `/users/sign_in` with `admin@admin.com` and `Password`.
