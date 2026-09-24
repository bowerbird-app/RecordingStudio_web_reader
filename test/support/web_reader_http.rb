# frozen_string_literal: true

require "minitest/mock"

module WebReaderHttp
  Response = Struct.new(:code, :headers, :body, :refuse_body, keyword_init: true) do
    def each_header
      headers.each { |key, value| yield(key.to_s, value.to_s) }
    end

    def read_body
      raise "response body was read" if refuse_body

      yield body.to_s
    end
  end

  class Client
    attr_reader :log
    attr_accessor :ipaddr, :use_ssl, :verify_mode, :open_timeout, :read_timeout, :write_timeout, :max_retries

    def initialize(queue, log)
      @queue = queue
      @log = log
    end

    def request(req)
      item = @queue.shift
      raise "no queued response for #{req.path}" if item.nil?

      @log << {
        ipaddr: ipaddr,
        use_ssl: use_ssl,
        verify_mode: verify_mode,
        open_timeout: open_timeout,
        read_timeout: read_timeout,
        write_timeout: write_timeout,
        range: req["Range"],
        user_agent: req["User-Agent"],
        path: req.path
      }
      raise item if item.is_a?(Exception)

      yield item if block_given?
      item
    end
  end

  def html_response(body, status: 200, headers: {})
    Response.new(
      code: status,
      headers: { "content-type" => "text/html; charset=utf-8" }.merge(headers),
      body: body
    )
  end

  def redirect_response(location, status: 302)
    Response.new(
      code: status,
      headers: { "location" => location, "content-type" => "text/html" },
      body: ""
    )
  end

  def png_bytes(width, height)
    signature = "\x89PNG\r\n\x1A\n".b
    data = [width, height, 8, 2, 0, 0, 0].pack("N2C5")
    chunk = "IHDR".b + data
    signature + [data.bytesize].pack("N") + chunk + [Zlib.crc32(chunk)].pack("N")
  end

  def with_network(responses, addresses: ["93.184.216.34"], &block)
    log = []
    client = Client.new(responses, log)
    resolver = addresses.respond_to?(:call) ? addresses : ->(*) { Array(addresses).dup }
    Resolv.stub(:getaddresses, resolver) do
      Net::HTTP.stub(:new, client, &block)
    end
    log
  end

  def read_page(url, responses, addresses: ["93.184.216.34"], **options)
    page = nil
    log = with_network(responses, addresses:) do
      page = RecordingStudio::WebReader.read(url, **options)
    end
    [page, log]
  end
end
