# frozen_string_literal: true

module RecordingStudio
  module WebReader
    module AiTool
      KEY = :visit_web_page
      VERSION = 2
      TEXT_LIMIT = 8_000
      LINK_LIMIT = 25
      IMAGE_LIMIT = 15
      FULL_TEXT_BYTES = 180_000
      FULL_LINK_LIMIT = 200
      FULL_IMAGE_LIMIT = 50
      RESULT_BYTE_BUDGET = 200_000

      DEFINITION = {
        key: KEY,
        version: VERSION,
        name: "Visit web page",
        description: "Visits one public http or https URL and returns the title, readable text, links, and images.",
        use_when: "A known URL needs to be read. Pass content full when the writing itself matters.",
        do_not_use_when: "The URL is not known yet, or the task is a web search.",
        parameters: [
          {
            name: :url,
            type: :string,
            required: true,
            description: "Absolute http or https URL."
          },
          {
            name: :content,
            type: :string,
            required: false,
            description: "summary returns a short reading. full returns the readable text, links, and images.",
            allowed_values: %w[summary full],
            default: "summary"
          }
        ],
        returns: "summary is a short reading. full returns the readable text. Raw HTML stays out.",
        cost: :low,
        latency: :slow,
        read_only: true,
        destructive: false,
        requires_confirmation: false,
        idempotent: true,
        executor_label: "RecordingStudio::WebReader.read",
        executor: ->(arguments, _context) { project(execute(arguments), content: arguments["content"]) }
      }.freeze

      def self.register!
        return unless defined?(::RecordingStudioAI)

        ::RecordingStudioAI.tools.register(**DEFINITION, override: true)
      end

      def self.execute(arguments)
        WebReader.read(arguments.fetch("url"))
      end

      def self.project(page, content: nil)
        full = content.to_s == "full"
        hash = observation(page, full: full)
        fit!(hash) if full
        hash
      end

      def self.observation(page, full:)
        hash = page.to_h
        hash.delete("html")
        assign_text(hash, full: full)
        hash["link_count"] = page.links.length
        hash["image_count"] = page.images.length
        hash["links"] = Array(hash["links"]).first(full ? FULL_LINK_LIMIT : LINK_LIMIT)
        hash["images"] = Array(hash["images"]).first(full ? FULL_IMAGE_LIMIT : IMAGE_LIMIT)
        hash["content"] = full ? "full" : "summary"
        hash
      end

      def self.assign_text(hash, full:)
        text = hash["text"].to_s
        if full
          hash["text_truncated"] = text.bytesize > FULL_TEXT_BYTES
          hash["text"] = hash["text_truncated"] ? text.byteslice(0, FULL_TEXT_BYTES).scrub : text
        else
          hash["text_truncated"] = text.length > TEXT_LIMIT
          hash["text"] = text[0, TEXT_LIMIT]
        end
      end

      def self.fit!(hash)
        while JSON.generate(hash).bytesize > RESULT_BYTE_BUDGET && hash["text"].bytesize > 1_000
          hash["text"] = hash["text"].byteslice(0, (hash["text"].bytesize * 0.8).to_i).scrub
          hash["text_truncated"] = true
        end
        hash
      end
    end
  end
end
