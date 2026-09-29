# Changelog

## [0.2.0] - 2026-09-29

### Added

- `:browser` is a built-in fetch strategy. `RecordingStudio::WebReader.read(url, strategy: :browser)` opens the page in Chrome and returns the rendered HTML.
- HTTP redirects from the browser are handed back to the reader, which checks the next URL before the next hop.
- A document request to a private or metadata address raises `UnsafeUrlError`. Other requests to those addresses are blocked.
- `config.chrome_path` chooses the Chrome binary. When it is nil, the gem looks at `GOOGLE_CHROME_BIN` and the usual Chrome and Chromium paths.

### Upgrade

- The default strategy stays `:http`. Existing `read` calls do not open Chrome.
- A host that already registered `:browser` must pass `override: true`, or that registration raises `RegistryError`.
- `strategy: :browser` raises `FetchError` when Chrome is not installed.

## [0.1.0] - 2026-09-24

### Added

- `RecordingStudio::WebReader.read` returns a normalized page for one public URL.
- HTTP fetching with redirect limits, timeouts, response size limits, and TLS verification.
- SSRF checks for the requested URL and every redirect.
- Title, description, canonical URL, Open Graph, Twitter, JSON-LD, main text, links, and images.
- Optional image dimension probe for PNG, GIF, JPEG, and WebP headers.
- Extractor and analysis registries with namespaces, evidence, and duplicate protection.
- Optional `visit_web_page` tool when Recording Studio AI is already loaded. Pass `content` `full` for the readable text. A large result drops metadata and links before it cuts the text.
- `probe_images` stops after 10 fetches.
- A fetcher must report the pinned address. Any other address is refused.
- `read.recording_studio_web_reader` and `probe_image.recording_studio_web_reader` notifications.
- An explicit caller-supplied cache.
- A dummy page that inspects a fetched page.
- `page.challenge` records a JavaScript interstitial without retrying the fetch.
- The dummy page can open a URL in Chrome when you choose **Open in a browser**.
- The dummy page asks Jev whether a paywall holds the writing back.
