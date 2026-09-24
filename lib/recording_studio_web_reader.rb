# frozen_string_literal: true

require "recording_studio"
require "recording_studio_web_reader/version"
require "recording_studio_web_reader/errors"
require "recording_studio_web_reader/configuration"
require "recording_studio_web_reader/page"
require "recording_studio_web_reader/safety"
require "recording_studio_web_reader/image_header"
require "recording_studio_web_reader/http"
require "recording_studio_web_reader/document"
require "recording_studio_web_reader/registry"
require "recording_studio_web_reader/read"
require "recording_studio_web_reader/ai_tool"
require "recording_studio_web_reader/host_boot"
require "recording_studio_web_reader/engine"

module RecordingStudio
  module WebReader
    DEFAULT_NAMESPACE = :recording_studio_web_reader

    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield configuration if block_given?
      end

      def read(url, strategy: nil, cache: nil, cache_ttl: 300)
        chosen = strategy.nil? ? configuration.fetch_strategy : strategy
        chosen = chosen.to_sym if chosen.respond_to?(:to_sym)
        return Read.call(url, strategy: chosen) unless cache

        Safety.resolve!(url)
        stored = cache_fetch(cache, cache_key(url, chosen), cache_ttl) do
          Read.call(url, strategy: chosen).to_h
        end
        Page.from_h(stored)
      end

      def probe_image(url)
        Read.probe_image(url)
      end

      def probe_images(page)
        raise ConfigurationError, "A page is required" unless page.is_a?(Page)

        seen = {}
        images = page.images.map do |image|
          next image if image[:width] && image[:height]

          url = image[:url]
          found = seen.fetch(url) do
            seen[url] = probe_image(url)
          rescue Error
            seen[url] = nil
          end
          next image unless found && found[:width] && found[:height]

          image.merge(
            width: found[:width],
            height: found[:height],
            aspect_ratio: found[:aspect_ratio],
            dimension_source: :image_probe
          )
        end
        page.with(images: images)
      end

      def register_extractor(name, callable = nil, namespace: DEFAULT_NAMESPACE, override: false, &block)
        registry.register(:extractor, name, callable || block, namespace:, override:)
      end

      def register_analysis(name, callable = nil, namespace: DEFAULT_NAMESPACE, override: false, &block)
        registry.register(:analysis, name, callable || block, namespace:, override:)
      end

      def register_fetcher(name, callable = nil, override: false, &block)
        registry.register_fetcher(name, callable || block, override:)
      end

      def extract(name, page, namespace: DEFAULT_NAMESPACE, **context)
        registry.call_extractor(name, page, namespace:, **context)
      end

      def analyze(name, page, namespace: DEFAULT_NAMESPACE, **context)
        registry.call_analysis(name, page, namespace:, **context)
      end

      def extensions
        registry.extensions
      end

      def reset_extensions!
        registry.clear_extensions!
      end

      private

      def registry
        @registry ||= Registry.new.tap { |registry| registry.register_fetcher(:http, Http, override: true) }
      end

      def cache_key(url, strategy)
        "recording_studio_web_reader/v1/#{strategy}/#{url}"
      end

      def cache_fetch(cache, key, ttl, &)
        raise ConfigurationError, "The cache must respond to fetch" unless cache.respond_to?(:fetch)

        parameters = cache.method(:fetch).parameters
        if parameters.any? { |type, name| %i[key keyrest].include?(type) || name == :expires_in }
          return cache.fetch(key, expires_in: ttl, &)
        end
        return cache.fetch(key, &) unless parameters.any? { |type, _name| %i[opt rest].include?(type) }

        options = { expires_in: ttl }
        cache.fetch(key, options, &)
      end
    end
  end
end
