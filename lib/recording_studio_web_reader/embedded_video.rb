# frozen_string_literal: true

require "json"

module RecordingStudio
  module WebReader
    # Title and description already embedded in a page's player JSON.
    class EmbeddedVideo
      MARKERS = %w[ytInitialPlayerResponse ytInitialData].freeze
      EQUALS = "=".ord
      OPEN_BRACE = "{".ord
      CLOSE_BRACE = "}".ord
      QUOTE = '"'.ord
      BACKSLASH = "\\".ord

      def self.from(doc)
        new(doc).to_h
      end

      def self.title(visible, embedded)
        chosen = embedded&.dig(:title).to_s
        return visible if chosen.empty? || visible.to_s.include?(chosen)

        chosen
      end

      def self.description(fallback, embedded)
        chosen = embedded&.dig(:description).to_s
        chosen.empty? ? fallback : chosen
      end

      def self.text(visible, embedded)
        parts = [lead(visible, embedded), visible].compact
        parts.reject!(&:empty?)
        text = parts.join(" ")
        text.empty? ? nil : text
      end

      def self.lead(visible, embedded)
        return if embedded.nil?

        pieces = []
        title = embedded[:title].to_s
        description = embedded[:description].to_s
        pieces << title unless title.empty? || visible.to_s.include?(title)
        pieces << description unless description.empty? || visible.to_s.include?(description)
        pieces.join(" ")
      end
      private_class_method :lead

      def initialize(doc)
        @doc = doc
      end

      def to_h
        found = blank
        @doc.css("script").each do |script|
          source = script.text
          next unless marked?(source)

          absorb_source(source, found)
          break if preferred?(found)
        end
        pack(found)
      end

      private

      def blank
        {
          title: nil,
          primary_title: nil,
          overlay_title: nil,
          short_description: nil,
          attributed_description: nil
        }
      end

      def marked?(source)
        MARKERS.any? { |marker| source.include?(marker) }
      end

      def preferred?(found)
        found[:title] && found[:short_description]
      end

      def absorb_source(source, found)
        MARKERS.each do |marker|
          absorb_marker(source, marker, found)
          break if preferred?(found)
        end
      end

      def absorb_marker(source, marker, found)
        from = 0
        while (index = source.byteindex(marker, from))
          brace = object_brace(source, index + marker.bytesize)
          json = brace && slice_json(source, brace)
          unless json
            from = (brace || index) + 1
            next
          end

          absorb_json(json, found)
          from = brace + json.bytesize
          break if preferred?(found)
        end
      end

      def object_brace(source, from)
        cursor = skip_space(source, from)
        return unless source.getbyte(cursor) == EQUALS

        cursor = skip_space(source, cursor + 1)
        cursor if source.getbyte(cursor) == OPEN_BRACE
      end

      def skip_space(source, cursor)
        cursor += 1 while space_byte?(source.getbyte(cursor))
        cursor
      end

      def space_byte?(byte)
        [32, 9, 10, 13].include?(byte)
      end

      def absorb_json(json, found)
        parsed = JSON.parse(json)
        absorb(parsed, found) if parsed.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end

      def absorb(object, found)
        stack = [object]
        until stack.empty?
          current = stack.pop
          push_node(stack, current, found)
        end
      end

      def push_node(stack, current, found)
        case current
        when Hash
          take(current, found)
          push_values(stack, current.values)
        when Array
          push_values(stack, current)
        end
      end

      def push_values(stack, values)
        index = values.length
        while index.positive?
          index -= 1
          stack << values[index]
        end
      end

      def take(hash, found)
        take_details(hash["videoDetails"], found)
        take_primary(hash["videoPrimaryInfoRenderer"], found)
        take_overlay(hash["playerOverlayVideoDetailsRenderer"], found)
        take_attributed(hash["attributedDescription"], found)
      end

      def take_details(details, found)
        return unless details.is_a?(Hash)

        found[:title] ||= text_value(details["title"])
        found[:short_description] ||= text_value(details["shortDescription"])
      end

      def take_primary(primary, found)
        return unless primary.is_a?(Hash)

        found[:primary_title] ||= renderer_title(primary["title"])
      end

      def take_overlay(overlay, found)
        return unless overlay.is_a?(Hash)

        found[:overlay_title] ||= renderer_title(overlay["title"])
      end

      def take_attributed(attributed, found)
        return unless attributed.is_a?(Hash)

        found[:attributed_description] ||= text_value(attributed["content"])
      end

      def renderer_title(node)
        return text_value(node["simpleText"]) if node.is_a?(Hash) && node["simpleText"].is_a?(String)
        return unless node.is_a?(Hash) && node["runs"].is_a?(Array)

        text_value(node["runs"].filter_map { |run| run["text"] if run.is_a?(Hash) }.join)
      end

      def text_value(value)
        return unless value.is_a?(String)

        text = value.gsub(/[[:space:]]+/, " ").strip
        text.empty? ? nil : text
      end

      def pack(found)
        title = found[:title] || found[:primary_title] || found[:overlay_title]
        description = found[:short_description] || found[:attributed_description]
        return if title.nil? && description.nil?

        { title: title, description: description }
      end

      def slice_json(source, start)
        depth = 0
        in_string = false
        escaped = false
        index = start
        while index < source.bytesize
          depth, in_string, escaped, done = step_json(source.getbyte(index), depth, in_string, escaped)
          return source.byteslice(start, index - start + 1).force_encoding(Encoding::UTF_8) if done

          index += 1
        end
        nil
      end

      def step_json(byte, depth, in_string, escaped)
        return string_step(byte, depth, escaped) if in_string
        return [depth, true, false, false] if byte == QUOTE
        return [depth + 1, false, false, false] if byte == OPEN_BRACE
        return [depth - 1, false, false, depth == 1] if byte == CLOSE_BRACE

        [depth, false, false, false]
      end

      def string_step(byte, depth, escaped)
        return [depth, true, false, false] if escaped
        return [depth, true, true, false] if byte == BACKSLASH
        return [depth, false, false, false] if byte == QUOTE

        [depth, true, false, false]
      end
    end
  end
end
