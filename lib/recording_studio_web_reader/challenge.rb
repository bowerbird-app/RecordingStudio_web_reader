# frozen_string_literal: true

module RecordingStudio
  module WebReader
    Challenge = Data.define(:kind, :evidence) do
      def to_h
        {
          "kind" => kind.to_s,
          "evidence" => evidence.map(&:to_h)
        }
      end

      def self.from_h(hash)
        return if hash.nil?

        data = hash.transform_keys(&:to_s)
        new(kind: data["kind"].to_s.to_sym, evidence: Array(data["evidence"]).map { |item| restore_evidence(item) })
      end

      def self.detect(doc, status:)
        script = script_src(doc)
        title = Document.title_for(doc)
        noscript = noscript_text(doc)
        title_hit = interstitial_title?(title) && javascript_request?(noscript)
        noscript_hit = blank_document?(doc) && javascript_request?(noscript)
        return unless script || title_hit || noscript_hit

        rows = [Evidence.new(source: :http, path: "status", value: status)]
        rows << Evidence.new(source: :html, path: "script", value: script) if script
        rows << Evidence.new(source: :html, path: "title", value: title) if title_hit
        rows << Evidence.new(source: :html, path: "noscript", value: noscript) if title_hit || noscript_hit
        new(kind: :javascript, evidence: rows)
      end

      def self.restore_evidence(item)
        fields = JsonValue.symbolize(item)
        source = fields[:source]
        source = source.to_sym if source.respond_to?(:to_sym)
        Evidence.new(source: source, path: fields[:path], value: fields[:value])
      end

      def self.script_src(doc)
        doc.css("script[src], iframe[src]").each do |node|
          src = node["src"].to_s
          return src if src.match?(%r{/cdn-cgi/challenge-platform|challenges\.cloudflare\.com}i)
        end
        nil
      end

      def self.interstitial_title?(title)
        title.to_s.match?(/\A(?:just a moment|checking your browser|attention required)\b/i)
      end

      def self.javascript_request?(text)
        text.to_s.match?(/javascript/i)
      end

      def self.noscript_text(doc)
        doc.css("noscript").map { |tag| Document.squish(tag.text) }.reject(&:empty?).join(" ")
      end

      def self.blank_document?(doc)
        copy = doc.dup
        copy.css(Document::CHROME).remove
        copy.css("[hidden], [aria-hidden='true']").remove
        node = copy.at_css("article") || copy.at_css("main") || copy.at_css("[role='main']") || copy.at_css("body")
        Document.squish(node&.text).empty?
      end
      private_class_method :restore_evidence, :script_src, :interstitial_title?, :javascript_request?,
                           :noscript_text, :blank_document?
    end
  end
end
