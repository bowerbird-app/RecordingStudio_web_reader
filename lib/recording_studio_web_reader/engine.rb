# frozen_string_literal: true

module RecordingStudio
  module WebReader
    class Engine < ::Rails::Engine
      isolate_namespace RecordingStudio::WebReader
      engine_name "recording_studio_web_reader"

      class << self
        def apply_model_extensions(target)
          apply_extensions(target, extensions_for(:model, extension_keys_for(target)))
        end

        def apply_controller_extensions(target)
          apply_extensions(target, extensions_for(:controller, extension_keys_for(target)))
        end

        def merge_yaml_config(app)
          return unless app.respond_to?(:config_for)

          yaml = begin
            app.config_for(:recording_studio_web_reader)
          rescue StandardError
            nil
          end
          RecordingStudio::WebReader.configuration.merge!(yaml) if yaml.respond_to?(:each)
        rescue StandardError
          nil
        end

        def merge_x_config(app)
          return unless app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio_web_reader)

          xcfg = app.config.x.recording_studio_web_reader
          if xcfg.respond_to?(:to_h)
            RecordingStudio::WebReader.configuration.merge!(xcfg.to_h)
          else
            merge_x_pairs(xcfg)
          end
        end

        private

        def merge_x_pairs(xcfg)
          hash = {}
          xcfg.each_pair { |key, value| hash[key] = value } if xcfg.respond_to?(:each_pair)
          RecordingStudio::WebReader.configuration.merge!(hash) if hash.any?
        rescue StandardError
          nil
        end

        def extensions_for(kind, names)
          hooks = RecordingStudio::WebReader.configuration.hooks
          Array(names).flat_map do |name|
            if kind == :model
              hooks.model_extensions_for(name)
            else
              hooks.controller_extensions_for(name)
            end
          end
        end

        def apply_extensions(target, extensions)
          return unless target

          applied = target.instance_variable_get(:@recording_studio_web_reader_applied_extensions) || identity_hash

          extensions.flatten.compact.each do |extension|
            next if applied[extension]

            target.class_eval(&extension)
            applied[extension] = true
          end

          target.instance_variable_set(:@recording_studio_web_reader_applied_extensions, applied)
        end

        def extension_keys_for(target)
          names = [target.name, target.name&.demodulize].compact.uniq
          names.map(&:to_sym)
        end

        def identity_hash
          {}.compare_by_identity
        end
      end

      initializer "recording_studio_web_reader.before_initialize",
                  before: "recording_studio_web_reader.load_config" do |_app|
        RecordingStudio::WebReader.configuration.hooks.run(:before_initialize, self)
      end

      initializer "recording_studio_web_reader.load_config" do |app|
        Engine.merge_yaml_config(app)
        Engine.merge_x_config(app)
        RecordingStudio::WebReader.configuration.hooks.run(:on_configuration, RecordingStudio::WebReader.configuration)
      end

      initializer "recording_studio_web_reader.after_initialize",
                  after: "recording_studio_web_reader.load_config" do |_app|
        RecordingStudio::WebReader.configuration.hooks.run(:after_initialize, self)
      end

      initializer "recording_studio_web_reader.apply_model_extensions" do
        config.to_prepare do
          HostBoot.prepare!
          next unless defined?(ActiveRecord::Base)

          ActiveRecord::Base.descendants.each do |model|
            next if model.abstract_class?

            RecordingStudio::WebReader::Engine.apply_model_extensions(model)
          end
        end
      end

      initializer "recording_studio_web_reader.apply_controller_extensions" do
        config.to_prepare do
          next unless defined?(ActionController::Base)

          ActionController::Base.descendants.each do |controller|
            RecordingStudio::WebReader::Engine.apply_controller_extensions(controller)
          end
        end
      end
    end
  end
end
