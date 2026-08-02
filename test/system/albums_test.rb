require "application_system_test_case"

class AlbumsTest < ApplicationSystemTestCase
  include LibraryTestHelper

  setup do
    create_test_song("a.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album_artist: "Neon Fields", album: "Afterglow", track_number: 1)
    create_test_song("b.mp3", title: "Second", artist: "Neon Fields",
      album_artist: "Neon Fields", album: "Afterglow", track_number: 2)
    create_test_song("c.mp3", title: "Elsewhere", artist: "Harbour Lights",
      album_artist: "Harbour Lights", album: "Tidal")
  end

  test "the nav reaches the album grid" do
    visit root_path
    click_on "Albums"

    assert_selector "h1", text: "Albums"
    assert_text "2 albums"
    assert_text "Afterglow"
    assert_text "Tidal"
  end

  test "searching filters the grid inside its frame" do
    visit albums_path

    fill_in "Search albums and album artists…", with: "Tidal"

    assert_text "1 album"
    assert_no_text "Afterglow"
  end

  test "an album card opens the album" do
    visit albums_path
    click_on "Afterglow"

    assert_selector "h1", text: "Afterglow"
    assert_text "Neon Fields"
    assert_text "2 songs"
    assert_selector "tbody tr", count: 2
    assert_selector "tbody tr:first-child", text: "Midnight Drive"
  end

  test "the nav stays on Albums while viewing one" do
    visit albums_path
    click_on "Afterglow"

    assert_selector "nav a[aria-current=page]", text: "Albums"
  end

  test "a track can be edited from the album page" do
    visit albums_path
    click_on "Afterglow"

    within("tbody tr:first-child") { click_on "Edit" }

    assert_selector "dialog h2", text: "Edit song"
    fill_in "Genre", with: "Synthwave"
    click_on "Save changes"

    assert_no_selector "dialog"
    assert_equal "Synthwave", Song.find_by(title: "Midnight Drive").genre
  end
end
