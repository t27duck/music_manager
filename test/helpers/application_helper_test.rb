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

  test "progress_color follows the state" do
    assert_equal "text-red-400", progress_color(status(state: :failed))
    assert_equal "text-emerald-400", progress_color(status(state: :completed))
    assert_equal "text-accent-400", progress_color(status(state: :running))
  end

  test "progress_bar_color follows the state" do
    assert_equal "bg-red-500", progress_bar_color(status(state: :failed))
    assert_equal "bg-emerald-500", progress_bar_color(status(state: :completed))
    assert_equal "bg-accent-500", progress_bar_color(status(state: :running))
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
