require "application_system_test_case"

class SongsTest < ApplicationSystemTestCase
  include LibraryTestHelper

  test "shows the empty state when there are no songs" do
    visit root_path

    assert_text "Your library is empty"
  end

  test "lists songs in the library" do
    create_test_song("a.mp3", title: "Midnight Drive", artist: "Neon Fields", album: "Afterglow",
      genre: "Synthwave", year: 2021, track_number: 3, duration: 245)

    visit root_path

    assert_selector "h1", text: "Songs"
    assert_text "1 song"

    within "tbody tr:first-child" do
      assert_text "Midnight Drive"
      assert_text "Neon Fields"
      assert_text "Afterglow"
      assert_text "Synthwave"
      assert_text "2021"
      assert_text "4:05"
    end
  end

  test "paginates through the library" do
    51.times do |i|
      create_test_song("song#{i}.mp3", artist: "Artist", title: format("Song %02d", i))
    end

    visit root_path

    assert_selector "tbody tr", count: 50
    assert_text "51 songs"

    within "nav[aria-label=pager]" do
      click_on "2"
    end

    assert_selector "tbody tr", count: 1
    assert_text "page 2 of 2"
  end

  test "highlights the current section in the navigation" do
    visit root_path

    assert_selector "nav a[aria-current=page]", text: "Songs"
  end
end
