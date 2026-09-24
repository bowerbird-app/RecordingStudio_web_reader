# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudio::WebReader::Configuration.new
  end

  def test_merge_updates_known_attributes
    @configuration.merge!(user_agent: "Acme", max_redirects: 9, fetch_strategy: :http)

    assert_equal "Acme", @configuration.user_agent
    assert_equal 9, @configuration.max_redirects
    assert_equal :http, @configuration.fetch_strategy
  end

  def test_merge_ignores_unknown_keys
    @configuration.merge!(unknown_key: "ignored", max_redirects: 7)

    refute_respond_to @configuration, :unknown_key
    assert_equal 7, @configuration.max_redirects
  end

  def test_merge_with_non_enumerable_is_noop
    original = @configuration.to_h

    @configuration.merge!(nil)

    assert_equal original[:user_agent], @configuration.user_agent
    assert_equal original[:max_redirects], @configuration.max_redirects
    assert_equal original[:fetch_strategy], @configuration.fetch_strategy
  end

  def test_nil_timeouts_fall_back_to_defaults
    @configuration.open_timeout = nil
    @configuration.read_timeout = nil
    @configuration.instrumentation_enabled = nil
    @configuration.fetch_strategy = nil

    assert_equal 5, @configuration.open_timeout
    assert_equal 10, @configuration.read_timeout
    assert_equal true, @configuration.instrumentation_enabled
    assert_equal :http, @configuration.fetch_strategy
  end

  def test_instrumentation_can_be_turned_off
    @configuration.instrumentation_enabled = false

    assert_equal false, @configuration.instrumentation_enabled
  end

  def test_merge_accepts_string_keys
    @configuration.merge!("user_agent" => "string-key", "max_redirects" => 12, "fetch_strategy" => "http")

    assert_equal "string-key", @configuration.user_agent
    assert_equal 12, @configuration.max_redirects
    assert_equal :http, @configuration.fetch_strategy
  end

  def test_to_h_reports_registered_hook_counts
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.after_service { nil }

    result = @configuration.to_h

    assert_equal 2, result.fetch(:hooks_registered).fetch(:before_initialize)
    assert_equal 1, result.fetch(:hooks_registered).fetch(:after_service)
    refute result.key?(:html)
  end

  def test_configure_without_block_is_safe
    RecordingStudio::WebReader.configure

    assert_kind_of RecordingStudio::WebReader::Configuration, RecordingStudio::WebReader.configuration
  end
end
