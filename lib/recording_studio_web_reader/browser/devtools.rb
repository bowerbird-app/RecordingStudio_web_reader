# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "socket"
require "uri"

module RecordingStudio
  module WebReader
    class Browser
      class Devtools
        def self.connect(port, deadline)
          uri = page_uri(port)
          socket = TCPSocket.new(uri.host, uri.port)
          session = new(socket)
          session.handshake(uri, deadline)
          session
        end

        def self.page_uri(port)
          http = Net::HTTP.new("127.0.0.1", port)
          http.open_timeout = 3
          http.read_timeout = 5
          response = http.send_request("PUT", "/json/new?about:blank")
          response = http.send_request("GET", "/json/new?about:blank") unless response.is_a?(Net::HTTPSuccess)
          raise FetchError, "The browser could not open the page" unless response.is_a?(Net::HTTPSuccess)

          URI(JSON.parse(response.body).fetch("webSocketDebuggerUrl"))
        end

        def initialize(socket)
          @socket = socket
          @buffer = +"".b
          @next_id = 0
        end

        def handshake(uri, deadline)
          key = Base64.strict_encode64(Random.bytes(16))
          @socket.write(handshake_request(uri, key))
          header = read_until("\r\n\r\n", deadline)
          raise FetchError, "The browser could not open the page" unless header.start_with?("HTTP/1.1 101")
        end

        def command(method, params = {}, deadline:)
          id = send_command(method, params)
          loop do
            message = read_message(deadline)
            yield message if block_given?
            return message.fetch("result", {}) if message["id"] == id
          end
        end

        def dispatch(method, params = {})
          send_command(method, params)
        end

        def read_message(deadline)
          JSON.parse(read_text(deadline))
        end

        def close
          @socket&.close
        rescue StandardError
          nil
        end

        private

        def handshake_request(uri, key)
          "GET #{uri.request_uri} HTTP/1.1\r\n" \
            "Host: #{uri.host}:#{uri.port}\r\n" \
            "Upgrade: websocket\r\n" \
            "Connection: Upgrade\r\n" \
            "Sec-WebSocket-Key: #{key}\r\n" \
            "Sec-WebSocket-Version: 13\r\n\r\n"
        end

        def send_command(method, params)
          @next_id += 1
          send_text(JSON.generate(id: @next_id, method: method, params: params))
          @next_id
        end

        def send_text(text)
          payload = text.b
          mask = Random.bytes(4)
          masked = payload.bytes.map.with_index { |byte, index| byte ^ mask.getbyte(index % 4) }.pack("C*")
          @socket.write(frame_header(payload.bytesize) + mask + masked)
        end

        def frame_header(length)
          prefix = [0x81].pack("C")
          return prefix + [0x80 | length].pack("C") if length < 126
          return prefix + [0x80 | 126, length].pack("Cn") if length < 65_536

          prefix + [0x80 | 127, length].pack("CQ>")
        end

        def read_text(deadline)
          payload = +"".b
          loop do
            byte0, byte1 = read_bytes(2, deadline).bytes
            finished = append_frame(payload, byte0, read_payload(byte1, deadline))
            return payload.force_encoding(Encoding::UTF_8) if finished == :done
          end
        end

        def append_frame(payload, byte0, data)
          opcode = byte0 & 0x0f
          if opcode == 9
            send_pong(data)
            return :open
          end
          raise FetchError, "The browser could not open the page" if opcode == 8

          payload << data if [0, 1, 2].include?(opcode)
          byte0.allbits?(0x80) ? :done : :open
        end

        def read_payload(byte1, deadline)
          length = byte1 & 0x7f
          length = read_bytes(2, deadline).unpack1("n") if length == 126
          length = read_bytes(8, deadline).unpack1("Q>") if length == 127
          length.positive? ? read_bytes(length, deadline) : +"".b
        end

        def send_pong(data)
          send_control(0xA, data)
        end

        def send_control(opcode, data)
          payload = data.to_s.b
          mask = Random.bytes(4)
          masked = payload.bytes.map.with_index { |byte, index| byte ^ mask.getbyte(index % 4) }.pack("C*")
          header = [0x80 | opcode, 0x80 | payload.bytesize].pack("CC")
          @socket.write(header + mask + masked)
        end

        def read_until(marker, deadline)
          pull(deadline) until @buffer.include?(marker)
          head, rest = @buffer.split(marker, 2)
          @buffer = rest.to_s.b
          "#{head}#{marker}"
        end

        def read_bytes(count, deadline)
          pull(deadline) while @buffer.bytesize < count
          chunk = @buffer.byteslice(0, count)
          @buffer = @buffer.byteslice(count..-1).to_s.b
          chunk
        end

        def pull(deadline)
          remaining = deadline - monotonic
          raise TimeoutError, "The request timed out" if remaining <= 0

          raise TimeoutError, "The request timed out" unless @socket.wait_readable(remaining)

          chunk = @socket.read_nonblock(65_536, exception: false)
          raise FetchError, "The browser could not open the page" if chunk.nil? || chunk == :wait_readable

          @buffer << chunk.b
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
