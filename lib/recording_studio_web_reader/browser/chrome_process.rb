# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module RecordingStudio
  module WebReader
    class Browser
      class ChromeProcess
        def initialize(hop)
          @hop = hop
        end

        def launch
          @resolver_rule = resolver_rule
          binary = Browser.binary_path
          raise FetchError, "A browser is not available on this machine" unless binary

          @profile = Dir.mktmpdir("web-reader-chrome")
          @pid = Process.spawn(binary, *arguments, pgroup: true, out: File::NULL, err: File::NULL)
          @port = wait_for_port
        end

        attr_reader :port

        def stop
          signal("TERM")
          signal("KILL")
          reap
        ensure
          remove_profile
        end

        private

        def arguments
          [
            "--headless=new",
            "--disable-gpu",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-dev-shm-usage",
            "--remote-debugging-port=0",
            "--remote-allow-origins=*",
            "--user-data-dir=#{@profile}",
            "--user-agent=#{@hop.fetch(:user_agent)}",
            "--host-resolver-rules=#{@resolver_rule}"
          ]
        end

        def resolver_rule
          "MAP #{rule_token(@hop.fetch(:host))} #{mapped_address}"
        end

        def mapped_address
          address = rule_token(@hop.fetch(:address))
          address.include?(":") ? "[#{address}]" : address
        end

        def rule_token(value)
          token = value.to_s
          raise FetchError, "The page could not be fetched" if token.match?(/[\s,;"'\\]/)

          token
        end

        def wait_for_port
          deadline = monotonic + open_timeout
          path = File.join(@profile, "DevToolsActivePort")
          loop do
            return Integer(File.read(path).lines.first) if File.exist?(path)
            raise FetchError, "A browser is not available on this machine" if monotonic > deadline

            sleep 0.05
          end
        end

        def open_timeout
          @hop.dig(:timeouts, :open) || 5
        end

        def signal(name)
          Process.kill(name, -@pid) if @pid
        rescue Errno::ESRCH, Errno::EPERM
          nil
        end

        def reap
          Process.wait(@pid) if @pid
        rescue Errno::ECHILD
          nil
        end

        def remove_profile
          FileUtils.remove_entry(@profile) if @profile
          @profile = nil
          @pid = nil
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
