# frozen_string_literal: true

require_relative "lib/recording_studio_web_reader/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_web_reader"
  spec.version     = RecordingStudio::WebReader::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_web_reader"
  spec.summary     = "Visit a web page and return a normalized observation"
  spec.description = "A Recording Studio addon that fetches a public http(s) page and returns " \
                     "status, metadata, text, links, and images. It does not decide what those " \
                     "observations mean."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/RecordingStudio_web_reader"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/RecordingStudio_web_reader/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"].reject do |path|
      path == ".cursor" || path.start_with?(".cursor/")
    end
  end

  spec.add_dependency "nokogiri", ">= 1.16"
  spec.add_dependency "rails", "~> 8.1.0"
  spec.add_dependency "recording_studio", "~> 4.2"
end
