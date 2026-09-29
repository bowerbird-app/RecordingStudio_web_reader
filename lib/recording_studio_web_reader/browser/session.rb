# frozen_string_literal: true

module RecordingStudio
  module WebReader
    class Browser
      class Session
        INTERSTITIAL = /\A(?:just a moment|checking your browser|attention required)\b/i

        def initialize(hop)
          @hop = hop
          @events = []
        end

        def render
          @process = ChromeProcess.new(@hop)
          @process.launch
          @deadline = monotonic + read_timeout
          @devtools = Devtools.connect(@process.port, @deadline)
          enable_page
          navigate
          @redirect ? redirect_result : page_result
        rescue ::Timeout::Error
          raise TimeoutError, "The request timed out"
        rescue Error
          raise
        rescue StandardError
          raise FetchError, "The browser could not open the page"
        ensure
          shutdown
        end

        private

        def enable_page
          devtools_command("Network.enable")
          devtools_command("Page.enable")
          devtools_command("Fetch.enable", patterns: fetch_patterns)
        end

        def fetch_patterns
          [
            { urlPattern: "*", requestStage: "Request" },
            { urlPattern: "*", resourceType: "Document", requestStage: "Response" }
          ]
        end

        def navigate
          devtools_command("Page.navigate", url: @hop.fetch(:url))
          raise @blocked if @blocked
          return if @redirect

          wait_for("Page.loadEventFired")
          raise @blocked if @blocked
        end

        def wait_for(method)
          loop do
            return if @redirect || @blocked
            return if @events.any? { |event| event["method"] == method }

            consume(@devtools.read_message(@deadline))
          end
        end

        def page_result
          headers = document_headers
          [document_status, headers, rendered_html, content_type_for(headers), nil]
        end

        def redirect_result
          headers = @redirect[:headers]
          [@redirect[:status], headers, "", headers["content-type"], @redirect[:location]]
        end

        def rendered_html
          html = ""
          loop do
            html = evaluate(outer_html).to_s
            break unless interstitial?(evaluate("document.title").to_s)
            break if monotonic > @deadline

            sleep 0.4
          end
          html
        end

        def outer_html
          "document.documentElement ? document.documentElement.outerHTML : ''"
        end

        def interstitial?(title)
          title.match?(INTERSTITIAL)
        end

        def evaluate(expression)
          result = devtools_command("Runtime.evaluate", expression: expression, returnByValue: true)
          result.dig("result", "value")
        end

        def document_status
          status = @document&.dig(:status) || last_document_status
          status.to_i.zero? ? 200 : status.to_i
        end

        def last_document_status
          last_document&.dig("response", "status")
        end

        def document_headers
          return @document[:headers] if @document

          Browser.header_map(last_document&.dig("response", "headers"))
        end

        def last_document
          @events.filter_map { |event| document_event(event) }.last
        end

        def document_event(event)
          return unless event["method"] == "Network.responseReceived"
          return unless event.dig("params", "type") == "Document"

          event["params"]
        end

        def content_type_for(headers)
          mime = headers["content-type"].to_s.split(";").first.to_s.strip
          mime.empty? ? "text/html" : mime
        end

        def devtools_command(method, params = {})
          @devtools.command(method, params, deadline: @deadline) { |message| consume(message) }
        end

        def consume(message)
          note_network(message)
          return handle_pause(message["params"]) if message["method"] == "Fetch.requestPaused"

          @events << message if message["method"]
        end

        def note_network(message)
          return unless message["method"] == "Network.requestWillBeSent"

          response = message.dig("params", "redirectResponse")
          return unless response

          @network_redirect = { status: response["status"].to_i, headers: Browser.header_map(response["headers"]) }
        end

        def handle_pause(params)
          decision = Browser.decision_for(
            params,
            redirect_captured: !@redirect.nil?,
            network_redirect: @network_redirect,
            hop_url: @hop.fetch(:url)
          )
          apply_decision(decision, params)
        end

        def apply_decision(decision, params)
          request_id = params.fetch("requestId")
          case decision.action
          when :redirect then remember_redirect(decision, request_id)
          when :continue_response then continue_response(decision, request_id)
          when :block then block_request(decision, request_id)
          when :fail then fail_request(request_id, "Aborted")
          else continue_request(request_id)
          end
        end

        def remember_redirect(decision, request_id)
          @redirect = decision.exchange
          fail_request(request_id, "Aborted")
        end

        def continue_response(decision, request_id)
          @document ||= decision.exchange
          dispatch("Fetch.continueResponse", requestId: request_id)
        end

        def continue_request(request_id)
          dispatch("Fetch.continueRequest", requestId: request_id)
        end

        def block_request(decision, request_id)
          fail_request(request_id, "BlockedByClient")
          @blocked = decision.error if decision.error
        end

        def fail_request(request_id, reason)
          dispatch("Fetch.failRequest", requestId: request_id, errorReason: reason)
        end

        def dispatch(method, params = {})
          @devtools.dispatch(method, params)
        end

        def read_timeout
          @hop.dig(:timeouts, :read) || 10
        end

        def shutdown
          @devtools&.close
          @process&.stop
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
