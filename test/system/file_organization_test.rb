require "application_system_test_case"

class FileOrganizationTest < ApplicationSystemTestCase
  include LibraryTestHelper

  setup do
    @song = create_test_song("loose/one.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album: "Afterglow", track_number: 7)
    @other = create_test_song("loose/two.mp3", title: "Coastline", artist: "Harbour Lights",
      album: "Tidal", track_number: 3)
  end

  def target(*parts) = File.join(@temp_dir, *parts)

  def open_organizer_for(*songs)
    songs.each { |song| find("##{dom_id(song, :select)}").check }
    assert_text "#{songs.size} selected"
    click_on "Organize files"
    assert_selector "dialog h2", text: "Organize"
  end

  test "the preview shows where files will go before anything moves" do
    visit root_path
    open_organizer_for @song

    assert_selector "#file_organization_preview", text: "Neon Fields/Afterglow/07 - Midnight Drive.mp3"
    assert File.exist?(@song.file_path), "the preview moved the file"
  end

  test "the preview updates as the template is edited" do
    visit root_path
    open_organizer_for @song

    fill_in "Path template", with: "<Genre>/<Title>"

    assert_selector "#file_organization_preview", text: "Unknown Genre/Midnight Drive.mp3"
  end

  test "an invalid template is explained and blocks the move" do
    visit root_path
    open_organizer_for @song

    fill_in "Path template", with: "no tokens at all"

    assert_selector "[role=alert]", text: /at least one token/
    assert File.exist?(@song.file_path)
  end

  test "applying the template moves the files and refreshes the list" do
    visit root_path
    open_organizer_for @song, @other

    click_on "Move 2 files"

    assert_no_selector "dialog"
    assert_text "2 files moved"

    assert_equal target("Neon Fields/Afterglow/07 - Midnight Drive.mp3"), @song.reload.file_path
    assert_equal target("Harbour Lights/Tidal/03 - Coastline.mp3"), @other.reload.file_path
    assert File.exist?(@song.file_path)
    assert File.exist?(@other.file_path)
  end

  test "directories vacated by the move are cleaned up" do
    visit root_path
    open_organizer_for @song, @other

    click_on "Move 2 files"
    assert_text "2 files moved"

    assert_not Dir.exist?(target("loose")), "the emptied source directory was left behind"
  end

  test "a custom template is remembered next time" do
    visit root_path
    open_organizer_for @song

    fill_in "Path template", with: "<Artist>/<Title>"
    assert_selector "#file_organization_preview", text: "Neon Fields/Midnight Drive.mp3"
    click_on "Move 1 file"
    assert_text "1 file moved"

    # The finished job refreshes every open page, so start from a settled one --
    # a selection made mid-refresh would be thrown away by the reload.
    visit root_path
    open_organizer_for @other

    assert_equal "<Artist>/<Title>", find_field("Path template").value
  end

  test "organizing preserves the active filter" do
    visit root_path
    fill_in placeholder: "Search title, artist, album or genre…", with: "Midnight"
    assert_selector "tbody tr", count: 1

    open_organizer_for @song
    click_on "Move 1 file"

    assert_text "1 file moved"
    assert_text "1 song"
    assert_no_text "Coastline"
  end
end
