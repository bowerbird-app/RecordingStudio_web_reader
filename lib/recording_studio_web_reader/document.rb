# frozen_string_literal: true

require "json"
require "nokogiri"
require "uri"

module RecordingStudio
  module WebReader
    module Document
      CHROME = "script, style, noscript, template, svg, iframe, canvas, nav, footer, header, aside, form"
      HTML_TYPES = %w[text/html application/xhtml+xml].freeze
      SECRET_HEADERS = %w[cookie set-cookie authorization proxy-authorization].freeze
      LAZY_ATTRIBUTES = %w[data-src data-lazy-src data-original].freeze

      module_function

      def html?(content_type, body)
        media = media_type(content_type)
        return true if HTML_TYPES.include?(media)
        return false unless media.empty?

        body.to_s.lstrip.match?(/\A(?:<!doctype html|<html|<head|<body)/i)
      end

      def media_type(content_type)
        content_type.to_s.split(";").first.to_s.strip.downcase
      end

      def public_headers(headers)
        headers.each_with_object({}) do |(name, value), result|
          key = name.to_s.downcase
          next if SECRET_HEADERS.include?(key)

          result[key] = value
        end
      end

      def interpret(exchange, url:, final_url:)
        body = exchange.fetch(:body).to_s
        doc = parse_html(body)
        base = final_url
        images = collect_images(doc, base)
        Page.new(
          url: url,
          final_url: final_url,
          status: exchange.fetch(:status),
          headers: public_headers(exchange.fetch(:headers)),
          content_type: media_type(exchange[:content_type]).then { |type| type.empty? ? "text/html" : type },
          title: title_for(doc),
          description: description_for(doc),
          canonical_url: canonical_for(doc, base),
          text: text_for(doc),
          html: body,
          metadata: metadata_for(doc),
          links: links_for(doc, base),
          images: images
        )
      end

      def parse_html(body)
        if defined?(Nokogiri::HTML5)
          Nokogiri::HTML5(body)
        else
          Nokogiri::HTML(body)
        end
      end

      def title_for(doc)
        squish(doc.at_css("title")&.text).then { |value| value.empty? ? nil : value }
      end

      def description_for(doc)
        content = meta_content(doc, "description") || meta_property(doc, "og:description")
        content&.empty? ? nil : content
      end

      def canonical_for(doc, base)
        href = doc.at_css("link[rel~='canonical']")&.[]("href")
        absolute_http(href, base)
      end

      def text_for(doc)
        copy = doc.dup
        copy.css(CHROME).remove
        copy.css("[hidden], [aria-hidden='true']").remove
        node = copy.at_css("article") || copy.at_css("main") || copy.at_css("[role='main']") || copy.at_css("body")
        text = squish(node&.text)
        text.empty? ? nil : text
      end

      def metadata_for(doc)
        Page::Metadata.new(
          open_graph: properties_with_prefix(doc, "og:"),
          twitter: twitter_for(doc),
          json_ld: json_ld_for(doc),
          article: article_for(doc),
          meta: named_meta(doc)
        )
      end

      def properties_with_prefix(doc, prefix)
        result = {}
        doc.css("meta[property]").each do |tag|
          property = tag["property"].to_s
          next unless property.start_with?(prefix)

          result[property.delete_prefix(prefix)] = tag["content"].to_s
        end
        result
      end

      def twitter_for(doc)
        result = properties_with_prefix(doc, "twitter:")
        doc.css("meta[name]").each do |tag|
          name = tag["name"].to_s
          next unless name.start_with?("twitter:")

          result[name.delete_prefix("twitter:")] ||= tag["content"].to_s
        end
        result
      end

      def named_meta(doc)
        result = {}
        doc.css("meta[name]").each do |tag|
          name = tag["name"].to_s.strip
          next if name.empty? || result.key?(name)

          result[name] = tag["content"].to_s
        end
        result
      end

      def article_for(doc)
        article = properties_with_prefix(doc, "article:")
        author = meta_content(doc, "author")
        article["author"] ||= author if author
        article
      end

      def json_ld_for(doc)
        doc.css("script").select { |script| json_ld_type?(script["type"]) }.flat_map do |script|
          parsed = JSON.parse(script.text)
          case parsed
          when Hash then [parsed]
          when Array then parsed.select { |item| item.is_a?(Hash) }
          else []
          end
        rescue JSON::ParserError
          []
        end
      end

      def json_ld_type?(value)
        value.to_s.split(";").first.to_s.strip.casecmp("application/ld+json").zero?
      end

      def links_for(doc, base)
        doc.css("a[href]").filter_map do |anchor|
          url = absolute_http(anchor["href"], base)
          next unless url

          {
            url: url,
            text: squish(anchor.text),
            rel: anchor["rel"].to_s.split(/\s+/).reject(&:empty?)
          }
        end
      end

      def collect_images(doc, base)
        images = []
        doc.css("img").each do |img|
          image = image_from_tag(img, base)
          images << image if image
        end
        append_meta_image(
          images, doc, base,
          property: "og:image",
          source: :open_graph,
          width_property: "og:image:width",
          height_property: "og:image:height"
        )
        append_meta_image(images, doc, base, property: "twitter:image", source: :twitter)
        images
      end

      def image_from_tag(img, base)
        srcset = img["srcset"].to_s.strip
        srcset = img["data-srcset"].to_s.strip if srcset.empty?
        variants = srcset_variants(srcset, base)
        chosen = first_http(
          [img["src"], *LAZY_ATTRIBUTES.map { |name| img[name] }],
          base
        )
        chosen ||= variants.first&.dig(:url)
        return unless chosen

        source = image_source(img, chosen, base, variants)
        width = pixels(img["width"])
        height = pixels(img["height"])
        build_image(url: chosen, alt: img["alt"].to_s, width: width, height: height, source: source, variants: variants)
      end

      def image_source(img, chosen, base, variants)
        src = absolute_http(img["src"], base)
        return :html_attribute if src == chosen
        return :srcset if variants.any? && LAZY_ATTRIBUTES.none? { |name| absolute_http(img[name], base) == chosen }

        :lazy_attribute
      end

      def append_meta_image(images, doc, base, property:, source:, width_property: nil, height_property: nil)
        url = absolute_http(meta_property(doc, property), base)
        return unless url
        return if images.any? { |image| image[:url] == url }

        width = pixels(meta_property(doc, width_property)) if width_property
        height = pixels(meta_property(doc, height_property)) if height_property
        images << build_image(url: url, alt: "", width: width, height: height, source: source, variants: [])
      end

      def build_image(url:, alt:, width:, height:, source:, variants:)
        {
          url: url,
          alt: alt,
          width: width,
          height: height,
          aspect_ratio: aspect_ratio(width, height),
          source: source,
          dimension_source: width && height ? :html_attribute : nil,
          variants: variants
        }
      end

      def srcset_variants(value, base)
        value.to_s.split(",").filter_map do |candidate|
          parts = candidate.strip.split(/\s+/)
          next if parts.empty?

          url = absolute_http(parts[0], base)
          next unless url

          hint = parts[1].to_s[/\A(\d+)w\z/, 1]
          { url: url, width_hint: hint&.to_i }
        end
      end

      def first_http(values, base)
        values.each do |value|
          url = absolute_http(value, base)
          return url if url
        end
        nil
      end

      def absolute_http(value, base)
        raw = value.to_s.strip
        return if raw.empty? || raw.start_with?("#")

        scheme = raw[/\A([a-z][a-z0-9+.-]*):/i, 1]
        return if scheme && !%w[http https].include?(scheme.downcase)

        uri = URI.join(base, raw)
        return unless uri.is_a?(URI::HTTP) && uri.host && uri.user.nil?

        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError
        nil
      end

      def pixels(value)
        text = value.to_s.strip
        return unless text.match?(/\A[1-9]\d*\z/)

        text.to_i
      end

      def aspect_ratio(width, height)
        return unless width && height&.positive?

        (width.to_f / height).round(3)
      end

      def meta_content(doc, name)
        present(doc.at_css("meta[name='#{name}']")&.[]("content"))
      end

      def meta_property(doc, property)
        return if property.nil?

        present(doc.at_css("meta[property='#{property}'], meta[name='#{property}']")&.[]("content"))
      end

      def present(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def squish(value)
        value.to_s.gsub(/[[:space:]]+/, " ").strip
      end
    end
  end
end
