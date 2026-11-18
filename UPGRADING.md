# Upgrading to 0.5.1

1. This gem still requires Recording Studio `>= 7.0`, `< 8.0`. The dummy and development Gemfiles pin tag `v7.7.1`, because Accessible 0.54 and API 1.15 need Recording Studio `>= 7.7`.
2. Also pin FlatPack `v0.1.378`, Accessible `v0.54.0`, Trashable `v1.2.0`, Cache `v0.7.0`, Metrics `v0.9.1`, Logs `v0.8.1`, AI `v0.25.0`, API `v1.15.0`, Admin `v2.19.0`, Icons `v0.4.1`, and Moveable `v6.0.1`. Root Switchable stays `v0.16.0`.
3. When the host loads Recording Studio API 1.12 or later, add `config/recording_studio_api.yml`. The dummy uses a minimal file with `shared: {}`.
4. Copy `add_owner_to_recording_studio_api_api_clients` when the host loads Recording Studio API 1.15. The dummy does. Hosts moving to Recording Studio 7.7 must run the Recording Studio 7.4, 7.5, and 7.7 root-index migrations. API 1.4 requires the 7.4 index, and API 1.7 requires the migrations through 7.7 (the 7.5 root invariant, then the 7.7 root index). Only this repo's dummy app leaves those Recording Studio migrations out.
5. API 1.15 declares `AdminApi` only when an admin root is configured. A host with no admin root should not list `RecordingStudioApi::AdminApi` in `config.recordable_types`.
6. `read` is unchanged. Default fetch strategy stays `:http`.

# Upgrading to 0.5.0

1. Require Recording Studio `>= 7.0`, `< 8.0`. The dummy pins tag `v7.0.0`.
2. `root_recording_for` only finds a root. Create one with `create_root_recording!(recordable, actor:)`. The dummy `authorize_write` callback allows a present actor, including when `recording`, `root_recording`, and `parent_recording` are nil.
3. Copy the Recording Studio events `root_recording_id` migration. Trashable 0.17 removed `kept_sql`; use `Recording.kept`. Admin 2.16 uses `access_recording_resolver`.
4. `read` is unchanged. Default fetch strategy stays `:http`.

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
