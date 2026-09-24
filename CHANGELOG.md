# Changelog

## [0.1.0] - 2026-09-24

### Added

- `RecordingStudio::WebReader.read` returns a normalized page for one public URL.
- HTTP fetching with redirect limits, timeouts, response size limits, and TLS verification.
- SSRF checks for the requested URL and every redirect.
- Title, description, canonical URL, Open Graph, Twitter, JSON-LD, main text, links, and images.
- Optional image dimension probe for PNG, GIF, JPEG, and WebP headers.
- Extractor and analysis registries with namespaces, evidence, and duplicate protection.
- Optional `visit_web_page` tool when Recording Studio AI is already loaded.
- `read.recording_studio_web_reader` and `probe_image.recording_studio_web_reader` notifications.
- An explicit caller-supplied cache.
- A dummy page that inspects a fetched page.
- `page.challenge` records a JavaScript interstitial without retrying the fetch.
- The dummy page can open a URL in Chrome when you choose **Open in a browser**.
