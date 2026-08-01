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
end
