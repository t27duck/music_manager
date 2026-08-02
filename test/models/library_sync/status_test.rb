require "test_helper"

class LibrarySync::StatusTest < ActiveSupport::TestCase
  def status(**overrides)
    LibrarySync::Status.new(
      **{ state: :running, current: 0, total: 0, filename: nil, errors: [], finished_at: nil,
          skipped: 0 },
      **overrides
    )
  end

  test "starting is a running status with nothing counted yet" do
    starting = LibrarySync::Status.starting

    assert_predicate starting, :running?
    assert_not_predicate starting, :finished?
    assert_equal 0, starting.percent
  end

  test "reports its state" do
    assert_predicate status(state: :running), :running?
    assert_predicate status(state: :completed), :completed?
    assert_predicate status(state: :failed), :failed?
  end

  test "running is the only unfinished state" do
    assert_not_predicate status(state: :running), :finished?
    assert_predicate status(state: :completed), :finished?
    assert_predicate status(state: :failed), :finished?
  end

  test "calculates whole percentages" do
    assert_equal 0, status(current: 0, total: 200).percent
    assert_equal 25, status(current: 50, total: 200).percent
    assert_equal 100, status(current: 200, total: 200).percent
  end

  test "rounds percentages" do
    assert_equal 33, status(current: 1, total: 3).percent
  end

  test "reads as zero percent before the file count is known" do
    assert_equal 0, status(current: 0, total: 0).percent
  end

  test "never exceeds 100 percent" do
    assert_equal 100, status(current: 300, total: 200).percent
  end

  test "formats a stable progress counter" do
    assert_equal "7/40", status(current: 7, total: 40).counter
  end

  test "reports whether any file failed" do
    assert_not_predicate status(errors: []), :errors?
    assert_predicate status(errors: [ "bad.mp3: broken" ]), :errors?
  end

  # The message lives on the Status rather than in a helper: the progress bar is
  # shared with operations that have no notion of a "skipped" file.
  test "message reports how many files were left unread" do
    assert_equal "Sync complete — 12 unchanged",
      status(state: :completed, skipped: 12).message
  end

  test "message says nothing about skipping when nothing was skipped" do
    assert_equal "Sync complete", status(state: :completed, skipped: 0).message
  end

  test "message describes a run in progress" do
    assert_equal "Scanning library…", status(state: :running, total: 0).message
    assert_equal "Syncing library…", status(state: :running, total: 9).message
    assert_equal "Sync failed", status(state: :failed).message
  end

  test "survives a round trip through the cache" do
    original = status(current: 3, total: 9, filename: "song.mp3")
    Rails.cache.write("status_test", original)

    assert_equal original, Rails.cache.read("status_test")
  end
end
