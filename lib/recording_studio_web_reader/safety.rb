# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "uri"

module RecordingStudio
  module WebReader
    # Decides which destinations a fetch may open. The HTTP strategy connects
    # to the address returned here and does not resolve the host again.
    module Safety
      Destination = Data.define(:url, :host, :port, :address, :https)

      BLOCKED_RANGES = [
        IPAddr.new("0.0.0.0/8"),
        IPAddr.new("10.0.0.0/8"),
        IPAddr.new("100.64.0.0/10"),
        IPAddr.new("127.0.0.0/8"),
        IPAddr.new("169.254.0.0/16"),
        IPAddr.new("172.16.0.0/12"),
        IPAddr.new("192.0.0.0/24"),
        IPAddr.new("192.0.2.0/24"),
        IPAddr.new("192.168.0.0/16"),
        IPAddr.new("198.18.0.0/15"),
        IPAddr.new("198.51.100.0/24"),
        IPAddr.new("203.0.113.0/24"),
        IPAddr.new("224.0.0.0/4"),
        IPAddr.new("240.0.0.0/4"),
        IPAddr.new("::/128"),
        IPAddr.new("::1/128"),
        IPAddr.new("fc00::/7"),
        IPAddr.new("fe80::/10"),
        IPAddr.new("ff00::/8")
      ].freeze

      BLOCKED_HOSTS = %w[
        localhost
        localhost.localdomain
        metadata.google.internal
        metadata.goog
      ].freeze

      module_function

      def resolve!(value)
        uri = parse(value)
        host = uri.host.to_s.downcase
        raise InvalidUrlError, "The URL is not valid" if host.empty?
        raise UnsafeUrlError, "The URL is not allowed" if blocked_host?(host) || blocked_name?(host)

        address = pinned_address(host)
        uri.fragment = nil
        uri.user = nil
        uri.password = nil
        Destination.new(
          url: uri.to_s,
          host: host,
          port: uri.port,
          address: address,
          https: uri.scheme == "https"
        )
      end

      def parse(value)
        text = value.to_s.strip
        raise InvalidUrlError, "The URL is not valid" if text.empty?

        uri = URI.parse(text)
        raise InvalidUrlError, "The URL is not valid" unless uri.is_a?(URI::HTTP)
        raise UnsafeUrlError, "The URL is not allowed" if uri.user || uri.password

        uri
      rescue URI::InvalidURIError
        raise InvalidUrlError, "The URL is not valid"
      end

      def blocked_host?(host)
        name = host.delete_suffix(".")
        return true if BLOCKED_HOSTS.include?(name)
        return true if name.end_with?(".localhost", ".metadata.google.internal", ".internal")

        false
      end

      def blocked_name?(host)
        host.match?(/\A\d+\z/) || host.include?("\\") || host.include?("@")
      end

      def pinned_address(host)
        if ip_literal?(host)
          raise UnsafeUrlError, "The URL is not allowed" if blocked_ip?(host)

          return IPAddr.new(host).to_s
        end

        addresses = Resolv.getaddresses(host)
        raise FetchError, "The page could not be fetched" if addresses.empty?
        raise UnsafeUrlError, "The URL is not allowed" if addresses.any? { |ip| blocked_ip?(ip) }

        addresses.first
      rescue Resolv::ResolvError
        raise FetchError, "The page could not be fetched"
      end

      def ip_literal?(host)
        IPAddr.new(host)
        true
      rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
        false
      end

      def blocked_ip?(ip)
        addr = IPAddr.new(ip)
        # IPv4#ipv4_mapped builds a mapped address. Only unwrap addresses that already are mapped.
        addr = addr.native if addr.ipv4_mapped?
        return true if addr.loopback? || addr.private? || addr.link_local?

        BLOCKED_RANGES.any? { |range| range.include?(addr) }
      rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
        true
      end
    end
  end
end
