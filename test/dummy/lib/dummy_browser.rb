# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "net/http"
require "socket"
require "tmpdir"
require "uri"

class DummyBrowser
  WAIT_SECONDS = 20

  def self.call(hop)
    new(hop).call
  end

  def initialize(hop)
    @hop = hop
  end

  def call
    chrome = Chrome.new(@hop)
    status, headers, body, content_type = chrome.render
    raise RecordingStudio::WebReader::ResponseTooLargeError, "The response is too large" if body.bytesize > @hop.fetch(:max_bytes)

    {
      status: status,
      headers: headers,
      body: body,
      content_type: content_type,
      location: nil,
      address: @hop.fetch(:address)
    }
  end

  class Chrome
    def initialize(hop)
      @hop = hop
      @events = []
      @blocked = nil
    end

    def render
      launch
      connect_page
      enable_page
      navigate
      html = rendered_html
      document = last_document
      [
        finished_status(document),
        document ? stringify_headers(document.dig("response", "headers")) : {},
        html,
        content_type_for(document)
      ]
    rescue RecordingStudio::WebReader::Error
      raise
    rescue StandardError
      raise RecordingStudio::WebReader::FetchError, "The browser could not open the page"
    ensure
      shutdown
    end

    private

    def launch
      @binary = [
        ENV["GOOGLE_CHROME_BIN"],
        "/usr/bin/google-chrome",
        "/usr/local/bin/google-chrome"
      ].compact.find { |path| File.executable?(path.to_s) }
      raise RecordingStudio::WebReader::FetchError, "A browser is not available on this machine" unless @binary

      @profile = Dir.mktmpdir("web-reader-chrome")
      @pid = Process.spawn(
        @binary,
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-dev-shm-usage",
        "--remote-debugging-port=0",
        "--remote-allow-origins=*",
        "--user-data-dir=#{@profile}",
        "--user-agent=#{@hop.fetch(:user_agent)}",
        "--host-resolver-rules=MAP #{@hop.fetch(:host)} #{mapped_address}",
        out: File::NULL,
        err: File::NULL
      )
      @port = wait_for_port
    end

    def mapped_address
      address = @hop.fetch(:address).to_s
      address.include?(":") ? "[#{address}]" : address
    end

    def wait_for_port
      deadline = monotonic + 8
      path = File.join(@profile, "DevToolsActivePort")
      loop do
        return Integer(File.read(path).lines.first) if File.exist?(path)

        raise RecordingStudio::WebReader::FetchError, "A browser is not available on this machine" if monotonic > deadline

        sleep 0.05
      end
    end

    def connect_page
      http = Net::HTTP.new("127.0.0.1", @port)
      http.open_timeout = 3
      http.read_timeout = 5
      response = http.send_request("PUT", "/json/new?about:blank")
      response = http.send_request("GET", "/json/new?about:blank") unless response.is_a?(Net::HTTPSuccess)
      raise RecordingStudio::WebReader::FetchError, "The browser could not open the page" unless response.is_a?(Net::HTTPSuccess)

      page = JSON.parse(response.body)
      uri = URI(page.fetch("webSocketDebuggerUrl"))
      @socket = TCPSocket.new(uri.host, uri.port)
      @buffer = +"".b
      @next_id = 0
      handshake(uri)
    end

    def handshake(uri)
      key = Base64.strict_encode64(Random.bytes(16))
      @socket.write(
        "GET #{uri.request_uri} HTTP/1.1\r\n" \
        "Host: #{uri.host}:#{uri.port}\r\n" \
        "Upgrade: websocket\r\n" \
        "Connection: Upgrade\r\n" \
        "Sec-WebSocket-Key: #{key}\r\n" \
        "Sec-WebSocket-Version: 13\r\n\r\n"
      )
      header = read_until("\r\n\r\n")
      raise RecordingStudio::WebReader::FetchError, "The browser could not open the page" unless header.start_with?("HTTP/1.1 101")
    end

    def enable_page
      command("Network.enable")
      command("Page.enable")
      command("Fetch.enable", patterns: [{ urlPattern: "*", resourceType: "Document", requestStage: "Request" }])
    end

    def navigate
      command("Page.navigate", url: @hop.fetch(:url))
      raise @blocked if @blocked

      wait_for("Page.loadEventFired")
      raise @blocked if @blocked
    end

    def rendered_html
      deadline = monotonic + WAIT_SECONDS
      html = ""
      loop do
        html = evaluate("document.documentElement ? document.documentElement.outerHTML : ''").to_s
        title = evaluate("document.title").to_s
        break unless title.match?(/\A(?:just a moment|checking your browser|attention required)\b/i)
        break if monotonic > deadline

        sleep 0.4
      end
      html
    end

    def evaluate(expression)
      result = command("Runtime.evaluate", expression: expression, returnByValue: true)
      result.dig("result", "value")
    end

    def last_document
      @events.filter_map { |event|
        next unless event["method"] == "Network.responseReceived"
        next unless event.dig("params", "type") == "Document"

        event["params"]
      }.last
    end

    def finished_status(document)
      status = document&.dig("response", "status").to_i
      status = 200 if status.zero? || [301, 302, 303, 307, 308].include?(status)
      status
    end

    def content_type_for(document)
      mime = document&.dig("response", "mimeType").to_s
      mime = mime.split(";").first.to_s.strip
      mime.empty? ? "text/html" : mime
    end

    def stringify_headers(headers)
      Array(headers).each_with_object({}) do |(key, value), result|
        result[key.to_s.downcase] = value.to_s
      end
    end

    def command(method, params = {})
      id = send_command(method, params)
      deadline = monotonic + WAIT_SECONDS
      loop do
        message = read_message(deadline)
        handle_pause(message["params"]) if message["method"] == "Fetch.requestPaused"
        return message.fetch("result", {}) if message["id"] == id

        @events << message if message["method"]
      end
    end

    def wait_for(method)
      deadline = monotonic + WAIT_SECONDS
      loop do
        return if @events.any? { |event| event["method"] == method }

        message = read_message(deadline)
        handle_pause(message["params"]) if message["method"] == "Fetch.requestPaused"
        @events << message if message["method"]
      end
    end

    def handle_pause(params)
      request_id = params.fetch("requestId")
      url = params.dig("request", "url").to_s
      if params["resourceType"] == "Document" && !document_allowed?(url)
        send_command("Fetch.failRequest", requestId: request_id, errorReason: "BlockedByClient")
        @blocked = RecordingStudio::WebReader::UnsafeUrlError.new("The URL is not allowed")
      else
        send_command("Fetch.continueRequest", requestId: request_id)
      end
    end

    def document_allowed?(url)
      return true if url == "about:blank" || url.start_with?("data:", "blob:")

      RecordingStudio::WebReader::Safety.resolve!(url)
      true
    rescue RecordingStudio::WebReader::UnsafeUrlError
      false
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
      length = payload.bytesize
      header = [0x81].pack("C")
      header << if length < 126
        [0x80 | length].pack("C")
      elsif length < 65_536
        [0x80 | 126, length].pack("Cn")
      else
        [0x80 | 127, length].pack("CQ>")
      end
      @socket.write(header + mask + masked)
    end

    def read_message(deadline)
      JSON.parse(read_text(deadline))
    end

    def read_text(deadline)
      payload = +"".b
      loop do
        byte0, byte1 = read_bytes(2, deadline).bytes
        opcode = byte0 & 0x0f
        length = byte1 & 0x7f
        length = read_bytes(2, deadline).unpack1("n") if length == 126
        length = read_bytes(8, deadline).unpack1("Q>") if length == 127
        data = length.positive? ? read_bytes(length, deadline) : +"".b
        if opcode == 9
          send_text_frame(0xA, data)
          next
        end
        raise RecordingStudio::WebReader::FetchError, "The browser could not open the page" if opcode == 8

        payload << data if [0, 1, 2].include?(opcode)
        return payload.force_encoding(Encoding::UTF_8) if (byte0 & 0x80) == 0x80
      end
    end

    def send_text_frame(opcode, data)
      payload = data.to_s.b
      mask = Random.bytes(4)
      masked = payload.bytes.map.with_index { |byte, index| byte ^ mask.getbyte(index % 4) }.pack("C*")
      header = [0x80 | opcode, 0x80 | payload.bytesize].pack("CC")
      @socket.write(header + mask + masked)
    end

    def read_until(marker)
      deadline = monotonic + 5
      until @buffer.include?(marker)
        pull(deadline)
      end
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
      raise RecordingStudio::WebReader::TimeoutError, "The request timed out" if remaining <= 0

      ready = IO.select([@socket], nil, nil, remaining)
      raise RecordingStudio::WebReader::TimeoutError, "The request timed out" unless ready

      chunk = @socket.read_nonblock(65_536, exception: false)
      raise RecordingStudio::WebReader::FetchError, "The browser could not open the page" if chunk.nil? || chunk == :wait_readable

      @buffer << chunk.b
    end

    def shutdown
      @socket&.close
      stop_process
      FileUtils.remove_entry(@profile) if @profile
    rescue StandardError
      nil
    end

    def stop_process
      return unless @pid

      Process.kill("TERM", @pid)
    rescue Errno::ESRCH
      nil
    ensure
      return unless @pid

      Process.kill("KILL", @pid) rescue nil
      Process.wait(@pid) rescue nil
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
