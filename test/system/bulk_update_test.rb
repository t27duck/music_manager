require "application_system_test_case"

class BulkUpdateTest < ApplicationSystemTestCase
  include LibraryTestHelper

  setup do
    @one = create_test_song("a.mp3", title: "One", artist: "Old Artist", album: "Old Album")
    @two = create_test_song("b.mp3", title: "Two", artist: "Old Artist", album: "Old Album")
    @three = create_test_song("c.mp3", title: "Three", artist: "Old Artist", album: "Old Album")
  end

  def select_song(song)
    find("##{dom_id(song, :select)}").check
  end

  test "the toolbar appears once something is selected and counts the selection" do
    visit root_path
    assert_no_selector "button", text: "Edit selected"

    select_song @one
    assert_text "1 selected"

    select_song @two
    assert_text "2 selected"
  end

  test "clearing the selection hides the toolbar" do
    visit root_path
    select_song @one
    assert_text "1 selected"

    click_on "Clear"

    assert_no_selector "button", text: "Edit selected"
    assert_not find("##{dom_id(@one, :select)}").checked?
  end

  test "select all checks every row, and unchecking it clears them" do
    visit root_path

    check "Select all songs on this page"
    assert_text "3 selected"

    uncheck "Select all songs on this page"
    assert_no_selector "button", text: "Edit selected"
  end

  test "the select-all box reflects a partial selection" do
    visit root_path
    select_song @one

    # Capybara has no matcher for the indeterminate property; ask the DOM.
    assert page.evaluate_script(
      "document.querySelector(\"input[aria-label='Select all songs on this page']\").indeterminate"
    )
  end

  test "bulk editing applies to the selection only" do
    visit root_path
    select_song @one
    select_song @two

    click_on "Edit selected"
    assert_selector "dialog h2", text: "Edit 2 songs"

    fill_in "Artist", with: "New Artist"
    click_on "Apply to 2 songs"

    assert_no_selector "dialog"
    assert_text "2 songs updated."

    assert_equal "New Artist", @one.reload.artist
    assert_equal "New Artist", @two.reload.artist
    assert_equal "Old Artist", @three.reload.artist
  end

  test "blank fields are left alone" do
    visit root_path
    select_song @one
    click_on "Edit selected"

    fill_in "Artist", with: "Only Artist Changes"
    click_on "Apply to 1 song"
    assert_text "1 song updated."

    @one.reload
    assert_equal "Only Artist Changes", @one.artist
    assert_equal "Old Album", @one.album
  end

  test "changes reach the files on disk" do
    visit root_path
    select_song @one

    click_on "Edit selected"
    fill_in "Genre", with: "Ambient"
    click_on "Apply to 1 song"
    assert_text "1 song updated."

    assert_equal "Ambient", tags_on_disk(@one.file_path)[:genre]
  end

  test "album art can be assigned across a selection" do
    visit root_path
    select_song @one
    select_song @two

    click_on "Edit selected"
    attach_file "Album art", fixture_file("cover.jpg")
    click_on "Apply to 2 songs"

    assert_text "2 songs updated."
    assert_predicate @one.reload, :album_art?
    assert_predicate @two.reload, :album_art?
  end

  test "a submission with no changes is refused" do
    visit root_path
    select_song @one

    click_on "Edit selected"
    click_on "Apply to 1 song"

    assert_selector "dialog [role=alert]", text: /at least one change/
    assert_equal "Old Artist", @one.reload.artist
  end

  test "a partial failure is reported and the successes stand" do
    File.binwrite(@two.file_path, "no longer valid audio")

    visit root_path
    select_song @one
    select_song @two

    click_on "Edit selected"
    fill_in "Artist", with: "New Artist"
    click_on "Apply to 2 songs"

    assert_text "1 song updated, 1 failed."
    assert_text "Could not write tags"
    assert_equal "New Artist", @one.reload.artist
  end

  test "bulk editing preserves the active filter" do
    visit root_path
    fill_in placeholder: "Search title, artist, album or genre…", with: "One"
    # Wait for the frame to finish swapping before touching a row, or the
    # checkbox goes stale mid-click.
    assert_selector "tbody tr", count: 1

    select_song @one
    assert_text "1 selected"
    click_on "Edit selected"
    fill_in "Genre", with: "Filtered"
    click_on "Apply to 1 song"

    assert_text "1 song updated."
    assert_text "1 song"
    assert_no_text "Two"
  end
end
