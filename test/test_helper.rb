# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "rails"
require "active_support/time"
Time.zone ||= "UTC"
require "recording_studio_web_reader"
require "json"
require "net/http"
require "resolv"

module WebReaderTestState
  def save_web_reader_state
    @saved_web_reader_configuration = RecordingStudio::WebReader.instance_variable_get(:@configuration)
    @saved_web_reader_registry = RecordingStudio::WebReader.instance_variable_get(:@registry)
  end

  def restore_web_reader_state
    RecordingStudio::WebReader.instance_variable_set(:@configuration, @saved_web_reader_configuration)
    RecordingStudio::WebReader.instance_variable_set(:@registry, @saved_web_reader_registry)
  end

  def isolate_web_reader_configuration
    RecordingStudio::WebReader.instance_variable_set(
      :@configuration,
      RecordingStudio::WebReader::Configuration.new
    )
  end

  def isolate_web_reader_registry
    RecordingStudio::WebReader.instance_variable_set(:@registry, nil)
  end
end

module Minitest
  class Test
    include WebReaderTestState
  end
end
