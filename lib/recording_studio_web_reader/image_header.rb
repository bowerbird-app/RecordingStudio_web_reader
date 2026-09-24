# frozen_string_literal: true

module RecordingStudio
  module WebReader
    module ImageHeader
      PNG = "\x89PNG\r\n\x1A\n".b
      JPEG_MARKERS = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].freeze

      module_function

      def dimensions(data)
        bytes = data.to_s.b
        png(bytes) || gif(bytes) || webp(bytes) || jpeg(bytes)
      end

      def png(bytes)
        return unless bytes.start_with?(PNG) && bytes.bytesize >= 24 && bytes[12, 4] == "IHDR"

        bytes[16, 8].unpack("NN")
      end

      def gif(bytes)
        return unless bytes.start_with?("GIF87a".b, "GIF89a".b) && bytes.bytesize >= 10

        bytes[6, 4].unpack("vv")
      end

      def webp(bytes)
        return unless bytes.bytesize >= 30 && bytes[0, 4] == "RIFF" && bytes[8, 4] == "WEBP"

        case bytes[12, 4]
        when "VP8 " then vp8(bytes)
        when "VP8L" then vp8l(bytes)
        when "VP8X" then vp8x(bytes)
        end
      end

      def vp8(bytes)
        return unless bytes[23, 3] == "\x9D\x01\x2A".b

        [bytes[26, 2].unpack1("v") & 0x3FFF, bytes[28, 2].unpack1("v") & 0x3FFF]
      end

      def vp8l(bytes)
        return unless bytes.getbyte(20) == 0x2F

        b1, b2, b3, b4 = bytes[21, 4].bytes
        width = 1 + (((b2 & 0x3F) << 8) | b1)
        height = 1 + (((b4 & 0x0F) << 10) | (b3 << 2) | ((b2 & 0xC0) >> 6))
        [width, height]
      end

      def vp8x(bytes)
        width = 1 + (bytes.getbyte(24) | (bytes.getbyte(25) << 8) | (bytes.getbyte(26) << 16))
        height = 1 + (bytes.getbyte(27) | (bytes.getbyte(28) << 8) | (bytes.getbyte(29) << 16))
        [width, height]
      end

      def jpeg(bytes)
        return unless bytes.start_with?("\xFF\xD8".b)

        index = 2
        while index + 8 < bytes.bytesize
          break unless bytes.getbyte(index) == 0xFF

          index += 1 while bytes.getbyte(index) == 0xFF
          marker = bytes.getbyte(index)
          index += 1
          length = bytes[index, 2]&.unpack1("n")
          return unless length && length >= 2

          if JPEG_MARKERS.include?(marker)
            return unless index + 7 < bytes.bytesize

            height, width = bytes[index + 3, 4].unpack("nn")
            return [width, height]
          end
          index += length
        end
        nil
      end
    end
  end
end
