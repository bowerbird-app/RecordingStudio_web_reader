# frozen_string_literal: true

module RecordingStudio
  module WebReader
    class Registry
      def initialize
        @fetchers = {}
        @extractors = {}
        @analyses = {}
      end

      def register_fetcher(name, callable, override:)
        key = name.to_sym
        raise RegistryError, "fetcher #{key} is already registered" if @fetchers.key?(key) && !override
        raise RegistryError, "A fetcher must respond to call" unless callable.respond_to?(:call)

        @fetchers[key] = callable
        key
      end

      def fetch_fetcher(name)
        @fetchers.fetch(name.to_sym) do
          raise ConfigurationError, "Unknown fetch strategy: #{name}"
        end
      end

      def register(kind, name, callable, namespace:, override:)
        key = [namespace.to_sym, name.to_sym]
        store = store_for(kind)
        raise RegistryError, "#{kind} #{key.first}/#{key.last} is already registered" if store.key?(key) && !override
        raise RegistryError, "A #{kind} must respond to call" unless callable.respond_to?(:call)

        store[key] = callable
        key
      end

      def call_extractor(name, page, namespace:, **context)
        invoke(fetch(:extractor, name, namespace), page, context)
      end

      def call_analysis(name, page, namespace:, **context)
        coerce_analysis(invoke(fetch(:analysis, name, namespace), page, context))
      end

      def clear_extensions!
        @extractors.clear
        @analyses.clear
      end

      def extensions
        rows = @fetchers.keys.map { |name| { kind: :fetcher, name: name } }
        rows.concat(extension_rows(:extractor, @extractors))
        rows.concat(extension_rows(:analysis, @analyses))
      end

      private

      def store_for(kind)
        case kind
        when :extractor then @extractors
        when :analysis then @analyses
        else raise RegistryError, "Unknown extension kind: #{kind}"
        end
      end

      def fetch(kind, name, namespace)
        store_for(kind).fetch([namespace.to_sym, name.to_sym]) do
          raise RegistryError, "Unknown #{kind} #{namespace}/#{name}"
        end
      end

      def invoke(callable, page, context)
        callable.call(page, **context)
      rescue ArgumentError
        raise unless context.empty?

        callable.call(page)
      end

      def coerce_analysis(value)
        return value if value.is_a?(AnalysisResult)

        hash = value.respond_to?(:to_h) ? value.to_h : nil
        raise RegistryError, "An analysis must return a result" unless hash.is_a?(Hash)

        data = hash.transform_keys(&:to_sym)
        AnalysisResult.new(
          value: data[:value],
          confidence: data[:confidence],
          reason: data[:reason],
          evidence: Array(data[:evidence]).map { |item| evidence_for(item) }
        )
      end

      def evidence_for(item)
        return item if item.is_a?(Evidence)

        data = item.respond_to?(:to_h) ? item.to_h.transform_keys(&:to_sym) : {}
        source = data[:source]
        source = source.to_sym if source.respond_to?(:to_sym) && !source.is_a?(Numeric)
        Evidence.new(source: source, path: data[:path], value: data[:value])
      end

      def extension_rows(kind, store)
        store.keys.map { |namespace, name| { kind: kind, namespace: namespace, name: name } }
      end
    end
  end
end
