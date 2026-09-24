# frozen_string_literal: true

module RecordingStudio
  module WebReader
    module HostBoot
      def self.prepare!
        AiTool.register!
      end
    end
  end
end
