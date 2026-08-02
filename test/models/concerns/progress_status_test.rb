require "test_helper"

class ProgressStatusTest < ActiveSupport::TestCase
  # A bare includer, so these test the mixin rather than any one operation.
  Example = Data.define(:state, :current, :total, :errors) do
    include ProgressStatus
  end

  def example(state: :running, current: 0, total: 0, errors: [])
    Example.new(state: state, current: current, total: total, errors: errors)
  end

  test "reports its state" do
    assert_predicate example(state: :running), :running?
    assert_predicate example(state: :completed), :completed?
    assert_predicate example(state: :failed), :failed?
  end

  # SyncRun stores state in a string column while the live statuses hold a
  # Symbol, and one mixin serves both.
  test "answers the same for a string state as for a symbol" do
    assert_predicate example(state: "running"), :running?
    assert_predicate example(state: "completed"), :completed?
    assert_predicate example(state: "failed"), :failed?
  end

  test "running is the only unfinished state" do
    assert_not_predicate example(state: :running), :finished?
    assert_predicate example(state: :completed), :finished?
    assert_predicate example(state: :failed), :finished?
  end

  test "calculates whole percentages" do
    assert_equal 50, example(current: 5, total: 10).percent
    assert_equal 33, example(current: 1, total: 3).percent
  end

  test "reads as zero percent before the total is known" do
    assert_equal 0, example(current: 0, total: 0).percent
  end

  test "never exceeds 100 percent" do
    assert_equal 100, example(current: 300, total: 200).percent
  end

  test "formats a stable counter" do
    assert_equal "7/40", example(current: 7, total: 40).counter
  end

  test "reports whether anything failed" do
    assert_not_predicate example(errors: []), :errors?
    assert_predicate example(errors: [ "bad.mp3: broken" ]), :errors?
  end
end
