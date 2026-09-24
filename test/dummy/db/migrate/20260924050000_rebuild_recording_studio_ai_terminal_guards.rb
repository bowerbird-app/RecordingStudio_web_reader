# frozen_string_literal: true

# The history trigger is created while correlation_id still exists, then later
# migrations drop that column. PostgreSQL keeps the old column list inside the
# function, so a finished Jev run cannot be saved. Rebuild the guards from the
# columns that remain.
class RebuildRecordingStudioAITerminalGuards < ActiveRecord::Migration[8.1]
  TERMINAL_TABLES = {
    recording_studio_ai_runs: %w[completed failed cancelled],
    recording_studio_ai_attempts: %w[completed failed cancelled],
    recording_studio_ai_custom_tool_invocations: %w[completed denied rejected failed cancelled],
    recording_studio_ai_batches: %w[completed partially_completed failed cancelled expired],
    recording_studio_ai_batch_items: %w[completed failed cancelled expired]
  }.freeze
  MUTABLE_TERMINAL_COLUMNS = %w[id metadata lock_version created_at updated_at].freeze

  def up
    return unless connection.adapter_name.match?(/PostgreSQL/i)

    TERMINAL_TABLES.each do |table, statuses|
      next unless table_exists?(table)

      execute "DROP TRIGGER IF EXISTS #{terminal_trigger(table)} ON #{table}"
      execute "DROP FUNCTION IF EXISTS #{terminal_function(table)}()"
      create_guard(table, statuses)
    end
  end

  def down = nil

  private

  def terminal_trigger(table) = "rsai_terminal_#{table.to_s.delete_prefix('recording_studio_ai_')}"
  def terminal_function(table) = "#{terminal_trigger(table)}_guard"

  def create_guard(table, statuses)
    columns = connection.columns(table).index_by(&:name)
    comparisons = (columns.keys - MUTABLE_TERMINAL_COLUMNS).map do |column|
      quoted = connection.quote_column_name(column)
      if columns.fetch(column).sql_type == "json"
        "(OLD.#{quoted})::jsonb IS DISTINCT FROM (NEW.#{quoted})::jsonb"
      else
        "OLD.#{quoted} IS DISTINCT FROM NEW.#{quoted}"
      end
    end.join(" OR ")
    quoted_statuses = statuses.map { |status| connection.quote(status) }.join(", ")

    execute <<~SQL
      CREATE FUNCTION #{terminal_function(table)}() RETURNS trigger AS $$
      BEGIN
        IF OLD.status IN (#{quoted_statuses}) AND (#{comparisons}) THEN
          RAISE EXCEPTION 'terminal execution history is immutable' USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
    execute <<~SQL
      CREATE TRIGGER #{terminal_trigger(table)}
      BEFORE UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION #{terminal_function(table)}();
    SQL
  end
end
