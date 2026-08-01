require "application_system_test_case"

class SearchTest < ApplicationSystemTestCase
  include LibraryTestHelper

  setup do
    create_test_song("a.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album: "Afterglow", genre: "Synthwave", year: 2021)
    create_test_song("b.mp3", title: "Morning Light", artist: "Harbour Lights",
      album: "Tidal", genre: "Indie", year: 2019)
    create_test_song("c.mp3", title: "Untagged Demo", artist: nil, album: nil, genre: nil)
  end

  test "searching as you type narrows the list without a page reload" do
    visit root_path
    assert_text "3 songs"

    fill_in placeholder: "Search title, artist, album or genre…", with: "Midnight"

    assert_text "1 song"
    assert_text "Midnight Drive"
    assert_no_text "Morning Light"
  end

  test "searching matches the artist as well as the title" do
    visit root_path

    fill_in placeholder: "Search title, artist, album or genre…", with: "Harbour"

    assert_text "Morning Light"
    assert_no_text "Midnight Drive"
  end

  test "the clear button resets the search" do
    visit root_path
    fill_in placeholder: "Search title, artist, album or genre…", with: "Midnight"
    assert_text "1 song"

    find("button[aria-label='Clear search']").click

    assert_text "3 songs"
    assert_text "Morning Light"
  end

  test "advanced filters combine" do
    visit root_path

    find("summary", text: "Advanced filters").click
    fill_in "Artist", with: "Neon"
    fill_in "Genre", with: "Synthwave"

    assert_text "1 song"
    assert_text "Midnight Drive"
  end

  test "filtering by missing metadata finds untagged songs" do
    visit root_path

    find("summary", text: "Advanced filters").click
    select "No artist", from: "Missing metadata"

    assert_text "1 song"
    assert_text "Untagged Demo"
  end

  test "clicking a column heading sorts the list" do
    visit root_path

    click_on "Title"
    # Wait for the frame to settle before enumerating rows, or the elements go
    # stale mid-read.
    assert_selector "tbody tr:first-child", text: "Midnight Drive"
    assert_equal [ "Midnight Drive", "Morning Light", "Untagged Demo" ], listed_titles

    click_on "Title"
    assert_selector "tbody tr:first-child", text: "Untagged Demo"
    assert_equal [ "Untagged Demo", "Morning Light", "Midnight Drive" ], listed_titles
  end

  test "a search with no matches explains itself and offers a way out" do
    visit root_path

    fill_in placeholder: "Search title, artist, album or genre…", with: "nothing matches this"
    assert_text "No songs match your filters"

    click_on "Clear filters"

    assert_text "3 songs"
  end

  test "filters survive a reload because they are in the URL" do
    visit root_path
    fill_in placeholder: "Search title, artist, album or genre…", with: "Midnight"
    assert_text "1 song"

    page.refresh

    assert_text "1 song"
    assert_text "Midnight Drive"
    assert_equal "Midnight", find("input[type=search]", match: :first).value
  end

  private
    def listed_titles
      all("tbody tr td:first-child").map(&:text)
    end
end
