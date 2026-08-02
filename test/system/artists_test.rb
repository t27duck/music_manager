require "application_system_test_case"

class ArtistsTest < ApplicationSystemTestCase
  include LibraryTestHelper

  setup do
    create_test_song("a.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album_artist: "Neon Fields", album: "Afterglow", track_number: 1)
    create_test_song("b.mp3", title: "Coastline", artist: "Neon Fields",
      album_artist: "Neon Fields", album: "Tidal", track_number: 1)
    create_test_song("c.mp3", title: "Guest Theme", artist: "Rozen",
      album_artist: "Various Artists", album: "Harmony of Heroes", track_number: 1)
  end

  test "the nav reaches the artist grid" do
    visit root_path
    click_on "Artists"

    assert_selector "h1", text: "Artists"
    assert_text "2 artists"
    assert_text "Neon Fields"
    assert_text "Various Artists"
  end

  # Artists -> Albums -> Songs, the whole point of the hierarchy.
  test "an artist leads to their albums and on to a track list" do
    visit artists_path
    click_on "Neon Fields"

    assert_selector "h1", text: "Neon Fields"
    assert_text "2 albums"

    click_on "Afterglow"

    assert_selector "h1", text: "Afterglow"
    assert_selector "tbody tr", text: "Midnight Drive"
  end

  test "an album links back to its artist" do
    visit artists_path
    click_on "Various Artists"
    click_on "Harmony of Heroes"

    click_on "Various Artists"

    assert_selector "h1", text: "Various Artists"
    assert_text "1 album"
  end

  test "searching filters the grid inside its frame" do
    visit artists_path

    fill_in "Search artists…", with: "Various"

    assert_text "1 artist"
    assert_no_text "Neon Fields"
  end

  test "the nav stays on Artists while viewing one" do
    visit artists_path
    click_on "Neon Fields"

    assert_selector "nav a[aria-current=page]", text: "Artists"
  end
end
