require "application_system_test_case"

class EditSongTest < ApplicationSystemTestCase
  include LibraryTestHelper

  setup do
    @song = create_test_song("a.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album: "Afterglow", genre: "Synthwave", year: 2021)
    create_test_song("b.mp3", title: "Morning Light", artist: "Harbour Lights")
  end

  def open_editor_for(title)
    find("tr", text: title).click_link("Edit")
    assert_selector "dialog h2", text: "Edit song"
  end

  test "editing a song updates the list without leaving the page" do
    visit root_path
    open_editor_for "Midnight Drive"

    fill_in "Title", with: "Midnight Cruise"
    fill_in "Artist", with: "Neon Fields Redux"
    click_on "Save changes"

    assert_no_selector "dialog"
    assert_text "Midnight Cruise"
    assert_text "Neon Fields Redux"
    assert_no_text "Midnight Drive"
    assert_text "Updated Midnight Cruise."
  end

  test "changes are written to the file on disk" do
    visit root_path
    open_editor_for "Midnight Drive"

    fill_in "Title", with: "Written Through"
    click_on "Save changes"
    assert_no_selector "dialog"

    assert_equal "Written Through", tags_on_disk(@song.file_path)[:title]
  end

  test "cancelling closes the modal and changes nothing" do
    visit root_path
    open_editor_for "Midnight Drive"

    fill_in "Title", with: "Discarded"
    click_on "Cancel"

    assert_no_selector "dialog"
    assert_text "Midnight Drive"
    assert_no_text "Discarded"
  end

  test "the modal can be reopened after being dismissed" do
    visit root_path
    open_editor_for "Midnight Drive"
    click_on "Cancel"
    assert_no_selector "dialog"

    open_editor_for "Midnight Drive"

    assert_selector "dialog"
  end

  test "editing preserves the active filter" do
    visit root_path
    fill_in placeholder: "Search title, artist, album or genre…", with: "Midnight"
    assert_text "1 song"

    open_editor_for "Midnight Drive"
    fill_in "Album", with: "Afterglow Deluxe"
    click_on "Save changes"

    assert_no_selector "dialog"
    # Still filtered: the other song has not reappeared.
    assert_text "1 song"
    assert_text "Afterglow Deluxe"
    assert_no_text "Morning Light"
  end

  test "deleting a song removes it from the library and disk" do
    path = @song.file_path

    visit root_path
    open_editor_for "Midnight Drive"

    accept_confirm { click_on "Delete song" }

    assert_no_selector "dialog"
    assert_text "Deleted Midnight Drive"
    assert_no_text "Midnight Drive"
    assert_text "1 song"
    assert_not File.exist?(path)
  end

  test "an unwritable file reports the error and keeps the modal open" do
    visit root_path
    File.binwrite(@song.file_path, "no longer valid audio")

    open_editor_for "Midnight Drive"
    fill_in "Title", with: "Doomed"
    click_on "Save changes"

    assert_selector "dialog [role=alert]", text: /Could not write tags/
    assert_equal "Midnight Drive", @song.reload.title
  end
end
