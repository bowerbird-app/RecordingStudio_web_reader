# frozen_string_literal: true

# This migration comes from recording_studio_ai (originally 20260813120000)
class RemoveLegacyRecordingStudioAIPersistenceColumns < ActiveRecord::Migration[8.1]
  # The current create migration no longer adds these columns. Skip the drop on a fresh database.
  def change
    drop_present :recording_studio_ai_runs,
                 :initiator_snapshot, :executor_snapshot, :impersonator_snapshot, :input_digest, :output_digest
    drop_present :recording_studio_ai_custom_tool_invocations,
                 :arguments_digest, :arguments_summary, :result_digest
    drop_present :recording_studio_ai_batches,
                 :initiator_snapshot, :executor_snapshot, :impersonator_snapshot
  end

  def drop_present(table, *names)
    present = names.select { |name| column_exists?(table, name) }
    remove_columns(table, *present) if present.any?
  end
end
