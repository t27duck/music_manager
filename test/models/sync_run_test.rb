require "test_helper"

class SyncRunTest < ActiveSupport::TestCase
  def status(**overrides)
    LibrarySync::Status.new(
      **{ state: :completed, current: 5, total: 5, filename: nil, errors: [],
          finished_at: Time.current, skipped: 0 },
      **overrides
    )
  end

  test "start! opens a running run" do
    run = SyncRun.start!(forced: true)

    assert_predicate run, :running?
    assert_predicate run, :forced?
    assert_nil run.finished_at
  end

  test "start! records an ordinary sync as not forced" do
    assert_not_predicate SyncRun.start!, :forced?
  end

  test "finish! copies the terminal status onto the run" do
    run = SyncRun.start!
    run.finish!(status(total: 12, skipped: 9, errors: [ "bad.mp3: broken" ]))

    run.reload
    assert_predicate run, :completed?
    assert_equal 12, run.total
    assert_equal 9, run.skipped
    assert_equal [ "bad.mp3: broken" ], run.failures
    assert_predicate run.finished_at, :present?
  end

  test "finish! records a failure" do
    run = SyncRun.start!
    run.finish!(status(state: :failed, errors: [ "disk on fire" ]))

    assert_predicate run.reload, :failed?
  end

  # An empty array serializes to NULL, because Active Record's serialized type
  # treats it as the coder's own default. NULL has to read back as [] or every
  # clean run would break the view.
  test "a run with no failures round-trips as an empty array" do
    run = SyncRun.start!
    run.finish!(status(errors: []))

    assert_nil run.reload.read_attribute_before_type_cast(:failures)
    assert_equal [], run.failures
    assert_not_predicate run, :errors?
  end

  test "failures are capped so one catastrophic run cannot bloat the table" do
    run = SyncRun.start!
    run.finish!(status(errors: Array.new(SyncRun::FAILURE_LIMIT + 20) { |i| "file#{i}.mp3: broken" }))

    assert_equal SyncRun::FAILURE_LIMIT, run.reload.failures.size
  end

  # Trimmed before the insert, so the table is bounded before the row that would
  # exceed the cap exists -- and a run that dies without finishing cannot leave
  # the cap unenforced.
  test "start! trims the history to KEEP runs" do
    (SyncRun::KEEP + 5).times { SyncRun.start! }

    assert_equal SyncRun::KEEP, SyncRun.count
  end

  test "start! never discards the run it is about to create" do
    (SyncRun::KEEP + 5).times { SyncRun.start! }

    assert_predicate SyncRun.recent.first, :persisted?
    assert_predicate SyncRun.recent.first, :running?
  end

  test "start! keeps the newest runs" do
    old = SyncRun.start!
    SyncRun::KEEP.times { SyncRun.start! }

    assert_not SyncRun.exists?(old.id), "the oldest run was not discarded"
  end

  test "recent orders newest first" do
    older = SyncRun.start!
    newer = SyncRun.start!

    assert_equal [ newer.id, older.id ], SyncRun.recent.pluck(:id)
  end

  # The only way a run stays "running" is the process dying mid-sync.
  test "a long-abandoned running run reads as stale" do
    run = SyncRun.start!
    assert_not_predicate run, :stale?

    run.update_column(:created_at, (ProgressReporting::STATUS_TTL + 1.minute).ago)

    assert_predicate run.reload, :stale?
  end

  test "a finished run is never stale" do
    run = SyncRun.start!
    run.finish!(status)
    run.update_column(:created_at, 1.year.ago)

    assert_not_predicate run.reload, :stale?
  end

  test "duration is nil until the run finishes" do
    run = SyncRun.start!
    assert_nil run.duration

    run.finish!(status)
    assert_operator run.duration, :>=, 0
  end

  # It renders through the same partial and helpers as a live status, so the
  # predicates have to answer for a string column as well as a Symbol.
  test "the progress predicates work against the string state column" do
    assert_predicate SyncRun.new(state: "running"), :running?
    assert_predicate SyncRun.new(state: "completed"), :completed?
    assert_predicate SyncRun.new(state: "failed"), :failed?
    assert_not_predicate SyncRun.new(state: "running"), :finished?
  end

  test "an unknown state is rejected" do
    assert_not SyncRun.new(state: "sideways").valid?
  end

  # `errors` on an Active Record model is the validation object and must stay
  # that way; only the two methods that read it are overridden.
  test "errors is still ActiveModel::Errors" do
    run = SyncRun.new(state: "sideways")
    run.validate

    assert_kind_of ActiveModel::Errors, run.errors
    assert_includes run.errors[:state], "is not included in the list"
  end
end
