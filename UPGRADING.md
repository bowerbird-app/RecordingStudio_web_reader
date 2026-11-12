# Upgrading to 0.4.0

1. `RecordingStudio::WebReader.read` is unchanged. Default fetch strategy stays `:http`. SSRF checks are unchanged.
2. When Recording Studio API is loaded, this gem registers `GET /recording_studio_api/api/v1/web_reader/read`. Callers need `:view` on the request root. The endpoint uses the host's configured fetch strategy and has no `strategy` query parameter. There is no new gemspec dependency. MCP advertises the endpoint from that registration; this gem does not add an MCP tool.
3. Dummy development and test now pin Recording Studio API `v0.21.3` plus Admin, Icons, Moveable, Redis, and FlatPack `v0.1.341`.

# Upgrading to 0.3.0

1. Require Recording Studio `>= 6.3.0`. The dummy pins tag `v6.3.0`.
2. `RecordingStudio::WebReader.configuration.layout` defaults to `RecordingStudio::DEFAULT_LAYOUT`. Assign a layout name, `false`, or a callable that accepts `controller:`. `RecordingStudio::Layout.accept` validates the value.
3. Call `recording_studio_layout` on engine controllers. Do not hard-code `layout "application"` and do not include `RecordingStudio::UsesDefaultLayout`.
4. Rails hosts should land on `8.1.4.1` with rack `>= 3.2.8`, nokogiri `>= 1.19.5`, loofah `>= 2.25.3`, and rails-html-sanitizer `>= 1.7.2`. Use Ruby `3.3.13` or a later `3.3`.
5. `read` still uses HTTP unless you pass `strategy:`. SSRF checks are unchanged.
