require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "toast_classes styles errors in red" do
    assert_includes toast_classes(:alert), "bg-red-950"
    assert_includes toast_classes("error"), "bg-red-950"
  end

  test "toast_classes styles warnings in amber" do
    assert_includes toast_classes(:warning), "bg-amber-950"
  end

  test "toast_classes falls back to the accent style" do
    assert_includes toast_classes(:notice), "border-accent-700"
  end

  test "sync_status_message reports how many files were left unread" do
    assert_equal "Sync complete — 12 unchanged", sync_status_message(status(skipped: 12))
  end

  test "sync_status_message says nothing about skipping when nothing was skipped" do
    assert_equal "Sync complete", sync_status_message(status(skipped: 0))
  end

  test "sync_status_message describes a run in progress" do
    assert_equal "Scanning library…", sync_status_message(status(state: :running, total: 0))
    assert_equal "Syncing library…", sync_status_message(status(state: :running, total: 9))
    assert_equal "Sync failed", sync_status_message(status(state: :failed))
  end

  private
    def status(**overrides)
      LibrarySync::Status.new(
        **{ state: :completed, current: 1, total: 1, filename: nil, errors: [],
            finished_at: Time.current, skipped: 0 },
        **overrides
      )
    end
end
