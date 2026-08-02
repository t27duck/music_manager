require "application_system_test_case"

class CrossPageSelectionTest < ApplicationSystemTestCase
  include LibraryTestHelper

  # 51 songs, so the list is two pages at the default 50 per page. Titles sort
  # so that "Aardvark" is first on page one and "Zebra" is alone on page two.
  setup do
    @first = create_test_song("a.mp3", title: "Aardvark", artist: "AAA")
    49.times { |i| create_test_song("m#{i}.mp3", title: "Middle #{i}", artist: "MMM") }
    @last = create_test_song("z.mp3", title: "Zebra", artist: "ZZZ")
  end

  def select_song(song)
    find("##{dom_id(song, :select)}").check
  end

  def go_to_page(number)
    within("nav[aria-label=pager]") { click_on number.to_s }
    assert_selector "#songs_count", text: "page #{number} of 2"
  end

  # The whole point: the selection used to live in the checkboxes, and every
  # frame re-render threw it away.
  test "a selection survives paging to the next page and back" do
    visit root_path

    select_song @first
    assert_text "1 selected"

    go_to_page 2
    assert page.has_text?("1 selected"), "the selection did not survive paging"

    select_song @last
    assert_text "2 selected"

    go_to_page 1
    assert_text "2 selected"
    assert find("##{dom_id(@first, :select)}").checked?,
      "the checkbox was not re-ticked when its row came back"
  end

  test "a selection survives filtering the list" do
    visit root_path

    select_song @first
    assert_text "1 selected"

    fill_in placeholder: "Search title, artist, album or genre…", with: "Zebra"
    assert_selector "tbody tr", count: 1

    assert page.has_text?("1 selected"), "the selection did not survive a filter"
  end

  test "a bulk edit applies across pages" do
    visit root_path

    select_song @first
    go_to_page 2
    select_song @last
    assert_text "2 selected"

    click_on "Edit selected"
    fill_in "Genre", with: "Cross Page"
    click_on "Apply to 2 songs"

    assert_text "2 songs updated"
    assert_equal "Cross Page", @first.reload.genre
    assert_equal "Cross Page", @last.reload.genre
  end

  test "clearing empties a selection made across pages" do
    visit root_path

    select_song @first
    go_to_page 2
    select_song @last
    assert_text "2 selected"

    click_on "Clear"

    assert_no_selector "[data-selection-target=actions]:not([hidden])"
  end

  # Two deliberate clicks before anything can touch the whole library.
  test "select all matching escalates beyond the current page" do
    visit root_path

    assert_no_text "Select all 51 matching"

    check "Select all songs on this page"
    assert_text "50 selected"

    click_on "Select all 51 matching"
    assert_text "All 51 selected"

    click_on "Edit selected"
    assert_selector "dialog h2", text: "Edit 51 songs"
  end

  test "select all matching applies to songs that were never rendered" do
    visit root_path

    check "Select all songs on this page"
    click_on "Select all 51 matching"
    click_on "Edit selected"

    fill_in "Genre", with: "Everything"
    click_on "Apply to 51 songs"
    assert_text "51 songs updated"

    # Zebra is on page two and was never on screen when the selection was made.
    assert_equal "Everything", @last.reload.genre
  end

  test "ticking a single song drops out of select all matching" do
    visit root_path

    check "Select all songs on this page"
    click_on "Select all 51 matching"
    assert_text "All 51 selected"

    find("##{dom_id(@first, :select)}").uncheck

    assert_text "49 selected"
  end
end
