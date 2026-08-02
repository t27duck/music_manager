require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "reading a key that was never set returns nil" do
    assert_nil Setting[:nothing_here]
  end

  test "writing creates the setting" do
    Setting[:path_template] = "<Artist>/<Title>"

    assert_equal "<Artist>/<Title>", Setting[:path_template]
  end

  test "writing the same key twice updates rather than duplicating" do
    Setting[:path_template] = "<Artist>/<Title>"

    assert_no_difference -> { Setting.count } do
      Setting[:path_template] = "<Genre>/<Title>"
    end

    assert_equal "<Genre>/<Title>", Setting[:path_template]
  end

  test "keys are interchangeably symbols and strings" do
    Setting[:path_template] = "<Title>"

    assert_equal "<Title>", Setting["path_template"]
  end

  test "writing returns the value, so it reads like an assignment" do
    assert_equal "<Title>", (Setting[:path_template] = "<Title>")
  end

  test "a duplicate key is rejected" do
    Setting.create!(key: "path_template", value: "<Title>")

    duplicate = Setting.new(key: "path_template", value: "<Artist>")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], "has already been taken"
  end

  test "a blank key is rejected" do
    assert_not Setting.new(value: "orphan").valid?
  end
end
