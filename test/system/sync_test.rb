require "application_system_test_case"

class SyncTest < ApplicationSystemTestCase
  include LibraryTestHelper

  test "syncing imports the library and reports progress live" do
    copy_fixture("Artist/Album/imported.mp3")

    visit root_path
    assert_text "Your library is empty"

    click_on "Sync library"

    # The completed bar arrives over Action Cable, not in the button's response:
    # seeing it proves the broadcast reached this page. visible: :all because the
    # bar starts fading itself out five seconds later.
    assert_text "Sync complete"
    assert_selector "[role=progressbar][aria-valuenow='100']", visible: :all

    # The list refreshes itself; no manual reload. "Test Song One" is the
    # fixture's own title tag.
    assert_text "Test Song One"
    assert_text "1 song"
  end

  test "the completed bar hides itself after a few seconds" do
    visit root_path
    click_on "Sync library"
    assert_text "Sync complete"

    assert_no_text "Sync complete"
  end

  test "removes songs whose files were deleted from disk" do
    kept = copy_fixture("kept.mp3")
    removed = copy_fixture("removed.mp3")

    visit root_path
    click_on "Sync library"
    assert_text "Sync complete"
    assert_text "2 songs"

    File.delete(removed)
    click_on "Sync library"
    assert_text "1 song"

    assert_equal [ kept ], songs_in_temp_dir.pluck(:file_path)
  end

  test "one unreadable file does not stop the rest of the library importing" do
    copy_fixture("good.mp3")
    File.binwrite(File.join(@temp_dir, "broken.mp3"), "not audio")

    visit root_path
    click_on "Sync library"

    assert_text "Sync complete"
    assert_text "1 file could not be imported"
    assert_equal 1, songs_in_temp_dir.count
  end
end
