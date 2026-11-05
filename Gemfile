# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_web_reader.gemspec
gemspec

# recording_studio is not published to RubyGems; resolve the gemspec pin from GitHub.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.341"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.3.0"

gem "bcrypt", ">= 3.1.22"
gem "devise", ">= 5.0.4"
gem "net-imap", ">= 0.6.4.1"
gem "puma", ">= 8.0.2"
gem "sprockets-rails"
gem "websocket-driver", ">= 0.8.2"

group :development, :test do
  gem "debug"
  gem "minitest", "~> 5.26"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
