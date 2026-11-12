# frozen_string_literal: true

# Dummy-only Accessible grants and tree placement. Not part of the gem API.
module DummyAccess
  module_function

  def as_actor(actor)
    previous = Current.actor
    Current.actor = actor
    yield
  ensure
    Current.actor = previous
  end

  def bootstrap_workspace!(name:, actor:)
    raise ArgumentError, "actor is required" if actor.blank?
    raise ArgumentError, "name is required" if name.blank?

    as_actor(actor) do
      workspace = Workspace.find_or_create_by!(name: name)
      root = RecordingStudio.root_recording_for(workspace)
      result = RecordingStudioAccessible.bootstrap_owner_access!(recording: root, actor: actor)
      raise(result.error.presence || "Accessible bootstrap failed") if result.failure?

      root
    end
  end
end
