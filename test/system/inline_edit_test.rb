require "application_system_test_case"

class InlineEditTest < ApplicationSystemTestCase
  include LibraryTestHelper

  setup do
    @song = create_test_song("a.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album: "Afterglow", genre: "Synthwave", year: 2021)
  end

  def cell(name)
    find("##{name}_song_#{@song.id}")
  end

  def start_editing(name)
    cell(name).double_click
    assert_selector "##{name}_song_#{@song.id} input"
  end

  test "double-clicking a cell opens an input" do
    visit root_path

    start_editing "title"

    assert_equal "Midnight Drive", cell("title").find("input").value
  end

  test "pressing Enter saves the change" do
    visit root_path
    start_editing "title"

    cell("title").find("input").set("Midnight Cruise")
    cell("title").find("input").send_keys(:enter)

    assert_no_selector "#title_song_#{@song.id} input"
    assert_text "Midnight Cruise"
    assert_equal "Midnight Cruise", @song.reload.title
  end

  test "clicking away saves the change" do
    visit root_path
    start_editing "artist"

    cell("artist").find("input").set("Neon Fields Redux")
    find("h1").click

    assert_no_selector "#artist_song_#{@song.id} input"
    assert_text "Neon Fields Redux"
    assert_equal "Neon Fields Redux", @song.reload.artist
  end

  test "pressing Escape discards the change" do
    visit root_path
    start_editing "album"

    cell("album").find("input").set("Discarded")
    cell("album").find("input").send_keys(:escape)

    assert_no_selector "#album_song_#{@song.id} input"
    assert_text "Afterglow"
    assert_no_text "Discarded"
    assert_equal "Afterglow", @song.reload.album
  end

  test "the change reaches the file on disk" do
    visit root_path
    start_editing "genre"

    cell("genre").find("input").set("Darkwave")
    cell("genre").find("input").send_keys(:enter)

    assert_text "Darkwave"
    assert_equal "Darkwave", tags_on_disk(@song.file_path)[:genre]
  end

  test "a cell can be edited again after saving" do
    visit root_path

    start_editing "title"
    cell("title").find("input").set("First Edit")
    cell("title").find("input").send_keys(:enter)
    assert_text "First Edit"

    start_editing "title"
    cell("title").find("input").set("Second Edit")
    cell("title").find("input").send_keys(:enter)

    assert_text "Second Edit"
    assert_equal "Second Edit", @song.reload.title
  end

  test "an empty cell can still be edited" do
    song = create_test_song("b.mp3", title: "No Genre", genre: nil)

    visit root_path
    find("#genre_song_#{song.id}").double_click

    assert_selector "#genre_song_#{song.id} input"
  end

  test "a failed write reports the error and keeps the input open" do
    visit root_path
    File.binwrite(@song.file_path, "no longer valid audio")

    start_editing "title"
    cell("title").find("input").set("Doomed")
    cell("title").find("input").send_keys(:enter)

    assert_selector "#title_song_#{@song.id} [role=alert]", text: /Could not write tags/
    assert_equal "Midnight Drive", @song.reload.title
  end

  test "editing one cell leaves the others alone" do
    visit root_path

    start_editing "title"
    cell("title").find("input").set("Only This")
    cell("title").find("input").send_keys(:enter)

    assert_text "Only This"
    assert_text "Neon Fields"
    assert_text "Afterglow"
    assert_text "Synthwave"
  end
end
