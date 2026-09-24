# frozen_string_literal: true

# This migration comes from recording_studio_ai (originally 20260814130000)
class RemoveCostColumnsFromRecordingStudioAI < ActiveRecord::Migration[8.1]
  COST_COLUMNS = {
    recording_studio_ai_runs: %i[cost_amount_microunits cost_currency cost_estimated],
    recording_studio_ai_attempts: %i[cost_amount_microunits cost_currency cost_estimated cost_source],
    recording_studio_ai_custom_tool_invocations: %i[cost_category],
    recording_studio_ai_batches: %i[cost_amount_microunits cost_currency cost_estimated],
    recording_studio_ai_batch_items: %i[cost_amount_microunits cost_currency cost_estimated]
  }.freeze

  def change
    remove_check_constraint :recording_studio_ai_attempts, name: "chk_rsai_attempts_cost_source" \
      if check_constraint_exists?(:recording_studio_ai_attempts, name: "chk_rsai_attempts_cost_source")
    if check_constraint_exists?(:recording_studio_ai_custom_tool_invocations,
                                name: "chk_rsai_tool_invocations_cost_category")
      remove_check_constraint :recording_studio_ai_custom_tool_invocations,
                              name: "chk_rsai_tool_invocations_cost_category"
    end
    # The current create migration no longer adds these columns. Skip the drop on a fresh database.
    COST_COLUMNS.each do |table, columns|
      present = columns.select { |name| column_exists?(table, name) }
      remove_columns table, *present if present.any?
    end
  end
end
