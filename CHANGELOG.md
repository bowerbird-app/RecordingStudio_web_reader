# Changelog

## [Unreleased]

## [0.4.0] - 2026-11-12

### Added

- Register `web_reader.read` on Recording Studio API when that gem is loaded. `GET web_reader/read` authorizes `:view` on the request root through Accessible and calls `RecordingStudio::WebReader.read`. MCP advertises the endpoint automatically.
- Dummy mounts Recording Studio API `v0.21.3` in development and test, with Admin, Icons, Moveable, and Redis so the engine can boot.

### Upgrade

- See `UPGRADING.md`. `read` is unchanged. Hosts that already load Recording Studio API get the endpoint after this version. There is no gemspec dependency on `recording_studio_api`.

## [0.3.0] - 2026-11-05

### Changed

- Require `recording_studio` `>= 6.3.0`. The dummy pins Recording Studio `v6.3.0`, Accessible `v0.24.1`, Trashable `v0.12.2`, Root Switchable `v0.11.5`, Cache `v0.6.2`, Metrics `v0.7.2`, Logs `v0.7.3`, AI `v0.19.6`, and FlatPack `v0.1.341`.
- `RecordingStudio::WebReader.configuration.layout` defaults to `RecordingStudio::DEFAULT_LAYOUT` and is validated by `RecordingStudio::Layout.accept`.
- Engine controllers call `recording_studio_layout`. Dummy pages drop FlatPack Card `style:`.
- Refresh both lockfiles to Rails `8.1.4.1`, rack `>= 3.2.8`, nokogiri `>= 1.19.5`, loofah `>= 2.25.3`, and rails-html-sanitizer `>= 1.7.2`. Local Ruby is `3.3.13`.
- Remove leftover template files (`UPDATE_SUMMARY.md`, `MIGRATION_NOTES.md`, `docs/gem_template/`).

### Upgrade

- See `UPGRADING.md`. `read` is unchanged. Default fetch strategy stays `:http`. Hosts must run Recording Studio `>= 6.3.0` and call `recording_studio_layout` instead of hard-coding `layout "application"`.

## [0.2.8] - 2026-11-02

### Changed

- `VERSION` is `0.2.8`. It now sits after tag `v0.2.7`.
- SimpleCov output under `coverage/` and `test/dummy/coverage/` is gitignored and untracked.
- Non-matrix GitHub Actions `ruby/setup-ruby` steps pin `ruby-version: '3.3'`. Matrix jobs still use the Ruby matrix.

### Upgrade

- `read` is unchanged. Default fetch strategy stays `:http`.

## [0.2.7] - 2026-10-14

### Changed

- Dummy pins Recording Studio `v4.6.0`, Accessible `v0.17.0`, AI `v0.11.0`, and Root Switchable `v0.9.0`.

## [0.2.6] - 2026-10-12

### Changed

- Dummy pins AI `v0.10.0`, Recording Studio `v4.5.0`, Accessible `v0.15.0`, and Root Switchable `v0.8.0`.

## [0.2.5] - 2026-10-09

### Changed

- Dummy pins Recording Studio `v4.4.0`.

## [0.2.4] - 2026-10-08

### Changed

- Dummy pins Recording Studio `v4.3.0`.

## [0.2.3] - 2026-10-05

### Changed

- Dummy credentials use the shared Recording Studio development master key.

## [0.2.2] - 2026-10-05

### Changed

- Dummy pins Recording Studio `v4.2.2`.

## [0.2.1] - 2026-09-29

### Fixed

- A page whose visible title is only the site name now uses the title and description embedded in that page's player JSON. Those words are placed ahead of the remaining visible text.
- A canonical href that is not a URL, such as `undefined`, stays nil.

### Upgrade

- Existing page attributes are unchanged. `read` still defaults to `:http` and does not treat this page as a JavaScript challenge.
- `page.canonical_url` is nil when the canonical href is not an absolute HTTP(S) URL or a relative path.

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

[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_web_reader/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_web_reader/compare/v0.2.8...v0.3.0
[0.2.8]: https://github.com/bowerbird-app/RecordingStudio_web_reader/compare/v0.2.7...v0.2.8
[0.2.7]: https://github.com/bowerbird-app/RecordingStudio_web_reader/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/bowerbird-app/RecordingStudio_web_reader/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/bowerbird-app/RecordingStudio_web_reader/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/bowerbird-app/RecordingStudio_web_reader/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/bowerbird-app/RecordingStudio_web_reader/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/bowerbird-app/RecordingStudio_web_reader/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_web_reader/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_web_reader/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_web_reader/releases/tag/v0.1.0
