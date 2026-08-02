require "application_system_test_case"

class SyncHistoryTest < ApplicationSystemTestCase
  include LibraryTestHelper

  test "a sync run from the library shows up in the history" do
    copy_fixture("a.mp3")
    copy_fixture("b.mp3")

    visit root_path
    click_on "Sync library"
    assert_text "Sync complete"

    click_on "Sync history"

    assert_selector "h1", text: "Sync history"
    within "tbody tr:first-child" do
      assert_text "Completed"
      assert_text "2"
    end
  end

  test "a full rescan is labelled as one" do
    copy_fixture("a.mp3")

    visit root_path
    click_on "Full rescan"
    assert_text "Sync complete"

    click_on "Sync history"

    assert_selector "tbody tr:first-child", text: "Full rescan"
  end

  test "failures are disclosed rather than shown inline" do
    File.binwrite(File.join(@temp_dir, "broken.mp3"), "not audio")

    visit root_path
    click_on "Sync library"
    assert_text "Sync complete"

    visit sync_runs_path

    assert_no_text "broken.mp3"
    # A <summary> is neither a link nor a button, so click_on cannot find it.
    find("summary", text: "1 file could not be imported").click
    assert_text "broken.mp3"
  end

  test "the history is empty before anything has run" do
    visit sync_runs_path

    assert_text "No syncs yet"
  end
end
