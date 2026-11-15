# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "test_helper"
require_relative "dummy/config/environment"

require "rails/test_help"

class RecordingStudioDeclarationsTest < ActiveSupport::TestCase
  setup do
    @actor = User.find_or_create_by!(email: "declarations@example.com") do |user|
      user.password = "Password123!"
      user.password_confirmation = "Password123!"
    end
    Current.actor = @actor
  end

  teardown do
    Current.actor = nil
  end

  test "dummy recordable declarations validate and expose parent/root introspection" do
    assert RecordingStudio.validate_recordable_declarations!
    assert_equal ["Workspace"], RecordingStudio.root_recordable_types
    assert_equal %w[Workspace Folder], RecordingStudio.allowed_parent_types_for("Folder")
    assert_equal %w[Workspace Folder], RecordingStudio.allowed_parent_types_for(Page)
  end

  test "root recordable creates a root recording" do
    workspace = Workspace.create!(name: unique_name("Root Workspace"))

    assert_nil RecordingStudio.root_recording_for(workspace)

    root_recording = RecordingStudio.create_root_recording!(workspace, actor: @actor)

    assert_predicate root_recording, :persisted?
    assert_equal workspace, root_recording.recordable
    assert_nil root_recording.parent_recording_id
    assert_equal root_recording.id, root_recording.root_recording_id
    assert_equal root_recording, RecordingStudio.root_recording_for(workspace)
  end

  test "allowed child can be recorded under a workspace root" do
    root_recording = RecordingStudio.create_root_recording!(
      Workspace.create!(name: unique_name("Child Workspace")),
      actor: @actor
    )
    folder = Folder.new(name: unique_name("Allowed Folder"))

    event = RecordingStudio.record!(
      action: "created",
      recordable: folder,
      root_recording: root_recording,
      parent_recording: root_recording
    )

    assert_equal folder, event.recording.recordable
    assert_equal root_recording, event.recording.parent_recording
  end

  test "page can be recorded under allowed workspace and folder parents" do
    root_recording = RecordingStudio.create_root_recording!(
      Workspace.create!(name: unique_name("Page Workspace")),
      actor: @actor
    )
    folder_recording = record_child(Folder.new(name: unique_name("Page Folder")), root_recording, root_recording)

    workspace_page_recording = record_child(
      Page.new(title: unique_name("Workspace Page")),
      root_recording,
      root_recording
    )
    folder_page_recording = record_child(Page.new(title: unique_name("Folder Page")), root_recording, folder_recording)

    assert_equal root_recording, workspace_page_recording.parent_recording
    assert_equal folder_recording, folder_page_recording.parent_recording
  end

  test "child recordable cannot be created as a root" do
    folder = Folder.create!(name: unique_name("Root Rejected Folder"))

    assert_raises(RecordingStudio::RootNotAllowed) do
      RecordingStudio.root_recording_for(folder)
    end
  end

  test "parentless child under an existing root is invalid" do
    root_recording = RecordingStudio.create_root_recording!(
      Workspace.create!(name: unique_name("Parentless Workspace")),
      actor: @actor
    )
    folder = Folder.create!(name: unique_name("Parentless Folder"))
    recording = RecordingStudio::Recording.new(root_recording: root_recording, recordable: folder)

    assert_not recording.valid?
    assert_includes recording.errors[:parent_recording_id].join, "cannot be blank"
  end

  test "page cannot be recorded under another page" do
    root_recording = RecordingStudio.create_root_recording!(
      Workspace.create!(name: unique_name("Invalid Page Workspace")),
      actor: @actor
    )
    page_recording = record_child(Page.new(title: unique_name("Parent Page")), root_recording, root_recording)

    error = assert_raises(RecordingStudio::InvalidParent) do
      record_child(Page.new(title: unique_name("Nested Page")), root_recording, page_recording)
    end
    assert_equal "Page cannot be recorded under Page", error.message
  end

  test "accessible is enabled on workspace and the template example capability stays off" do
    assert RecordingStudio.capability_enabled?(:accessible, for: "Workspace")
    refute RecordingStudio.capability_enabled?(:accessible, for: "Folder")
    refute RecordingStudio.capability_enabled?(:accessible, for: "Page")

    refute RecordingStudio.capability_enabled?(:example, for: "Workspace")
    refute RecordingStudio.capability_enabled?(:example, for: "Folder")
    refute RecordingStudio.capability_enabled?(:example, for: "Page")
  end

  private

  def record_child(recordable, root_recording, parent_recording)
    RecordingStudio.record!(
      action: "created",
      recordable: recordable,
      root_recording: root_recording,
      parent_recording: parent_recording
    ).recording
  end

  def unique_name(prefix)
    "#{prefix} #{SecureRandom.hex(4)}"
  end
end
