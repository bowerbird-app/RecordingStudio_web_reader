# frozen_string_literal: true

module RecordingStudio
  module WebReader
    module JsonValue
      module_function

      def stringify(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify(item) }
        when Array
          value.map { |item| stringify(item) }
        when Symbol
          value.to_s
        else
          value
        end
      end

      def symbolize(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), result| result[key.to_sym] = symbolize(item) }
        when Array
          value.map { |item| symbolize(item) }
        else
          value
        end
      end
    end

    Evidence = Data.define(:source, :path, :value) do
      def to_h
        JsonValue.stringify({ source: source, path: path, value: value })
      end
    end

    AnalysisResult = Data.define(:value, :confidence, :reason, :evidence) do
      def to_h
        {
          "value" => JsonValue.stringify(value),
          "confidence" => confidence,
          "reason" => reason,
          "evidence" => evidence.map(&:to_h)
        }
      end
    end

    Page = Data.define(
      :url, :final_url, :status, :headers, :content_type,
      :title, :description, :canonical_url, :text, :html,
      :metadata, :links, :images
    ) do
      def extract(name, namespace: WebReader::DEFAULT_NAMESPACE, **context)
        WebReader.extract(name, self, namespace:, **context)
      end

      def analyze(name, namespace: WebReader::DEFAULT_NAMESPACE, **context)
        WebReader.analyze(name, self, namespace:, **context)
      end

      def to_h
        JsonValue.stringify(
          {
            url: url,
            final_url: final_url,
            status: status,
            headers: headers,
            content_type: content_type,
            title: title,
            description: description,
            canonical_url: canonical_url,
            text: text,
            html: html,
            metadata: {
              open_graph: metadata.open_graph,
              twitter: metadata.twitter,
              json_ld: metadata.json_ld,
              article: metadata.article,
              meta: metadata.meta
            },
            links: links,
            images: images
          }
        )
      end

      def self.from_h(hash)
        data = hash.transform_keys(&:to_s)
        meta = (data["metadata"] || {}).transform_keys(&:to_s)
        new(
          url: data["url"],
          final_url: data["final_url"],
          status: data["status"],
          headers: (data["headers"] || {}).transform_keys(&:to_s),
          content_type: data["content_type"],
          title: data["title"],
          description: data["description"],
          canonical_url: data["canonical_url"],
          text: data["text"],
          html: data["html"],
          metadata: Page::Metadata.new(
            open_graph: meta.fetch("open_graph", {}),
            twitter: meta.fetch("twitter", {}),
            json_ld: meta.fetch("json_ld", []),
            article: meta.fetch("article", {}),
            meta: meta.fetch("meta", {})
          ),
          links: Array(data["links"]).map { |link| JsonValue.symbolize(link) },
          images: Array(data["images"]).map { |image| restore_image(image) }
        )
      end

      def self.restore_image(image)
        restored = JsonValue.symbolize(image)
        restored[:source] = restored[:source]&.to_sym
        restored[:dimension_source] = restored[:dimension_source]&.to_sym
        restored
      end
    end

    Page::Metadata = Data.define(:open_graph, :twitter, :json_ld, :article, :meta) do
      def to_h
        JsonValue.stringify(
          {
            open_graph: open_graph,
            twitter: twitter,
            json_ld: json_ld,
            article: article,
            meta: meta
          }
        )
      end
    end
  end
end
