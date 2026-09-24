# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RecordingStudio
  module WebReader
    module Generators
      class MigrationsGenerator < Rails::Generators::Base
        include ActiveRecord::Generators::Migration

        source_root File.expand_path("../../../..", __dir__)

        desc "Copy Recording Studio Web Reader migrations to your application"

        class_option :skip_existing, type: :boolean, default: true,
                                     desc: "Skip migrations that already exist (based on name, ignoring timestamp)"

        def copy_migrations
          migrations_dir = File.join(self.class.source_root, "db", "migrate")

          unless File.directory?(migrations_dir)
            say "No migrations found in Recording Studio Web Reader.", :yellow
            return
          end

          migration_files = Dir.glob(File.join(migrations_dir, "*.rb"))

          if migration_files.empty?
            say "No migrations found in Recording Studio Web Reader.", :yellow
            return
          end

          say "Found #{migration_files.size} migration(s) to install:", :green

          migration_files.each do |source_path|
            filename = File.basename(source_path)
            migration_name = filename.sub(/^\d+_/, "")

            if options[:skip_existing] && migration_exists?(migration_name)
              say "  skip  #{migration_name} (already exists)", :yellow
              next
            end

            timestamp = next_migration_number
            destination_filename = "#{timestamp}_#{migration_name}"
            destination_path = File.join("db/migrate", destination_filename)

            copy_file source_path, destination_path
            say "  create  #{destination_path}", :green

            sleep 0.1
          end

          say "\nRun 'bin/rails db:migrate' to apply the migrations.", :green
        end

        private

        def migration_exists?(migration_name)
          Dir.glob(File.join(destination_root, "db/migrate", "*_#{migration_name}")).any?
        end

        def next_migration_number
          ActiveRecord::Migration.next_migration_number(
            Time.now.utc.strftime("%Y%m%d%H%M%S")
          )
        end
      end
    end
  end
end
