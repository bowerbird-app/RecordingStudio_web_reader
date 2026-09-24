# frozen_string_literal: true

module RecordingStudio
  module WebReader
    module AiTool
      KEY = :visit_web_page
      VERSION = 1
      TEXT_LIMIT = 8_000
      LINK_LIMIT = 25
      IMAGE_LIMIT = 15

      DEFINITION = {
        key: KEY,
        version: VERSION,
        name: "Visit web page",
        description: "Visits one public http or https URL and returns the title, text, metadata, links, and images.",
        use_when: "A known URL needs to be read.",
        do_not_use_when: "The URL is not known yet, or the task is a web search.",
        parameters: [
          {
            name: :url,
            type: :string,
            required: true,
            description: "Absolute http or https URL."
          }
        ],
        returns: "A page observation without raw HTML. Text, links, and images are capped.",
        cost: :low,
        latency: :slow,
        read_only: true,
        destructive: false,
        requires_confirmation: false,
        idempotent: true,
        executor_label: "RecordingStudio::WebReader.read",
        executor: ->(arguments, _context) { project(execute(arguments)) }
      }.freeze

      def self.register!
        return unless defined?(::RecordingStudioAI)

        ::RecordingStudioAI.tools.register(**DEFINITION, override: true)
      end

      def self.execute(arguments)
        WebReader.read(arguments.fetch("url"))
      end

      def self.project(page)
        hash = page.to_h
        hash.delete("html")
        text = hash["text"].to_s
        hash["text_truncated"] = text.length > TEXT_LIMIT
        hash["text"] = text[0, TEXT_LIMIT]
        hash["link_count"] = page.links.length
        hash["image_count"] = page.images.length
        hash["links"] = Array(hash["links"]).first(LINK_LIMIT)
        hash["images"] = Array(hash["images"]).first(IMAGE_LIMIT)
        hash
      end
    end
  end
end
