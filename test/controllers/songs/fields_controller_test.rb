require "test_helper"

class Songs::FieldsControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper

  test "show renders the read-only cell" do
    song = create_test_song("a.mp3", title: "Midnight Drive")

    get song_field_url(song, "title")

    assert_response :success
    assert_select "turbo-frame#title_song_#{song.id}", text: /Midnight Drive/
    assert_select "input", count: 0
  end

  test "edit renders an input inside the cell's frame" do
    song = create_test_song("a.mp3", title: "Midnight Drive")

    get edit_song_field_url(song, "title")

    assert_response :success
    assert_select "turbo-frame#title_song_#{song.id} input[name='song[title]'][value='Midnight Drive']"
  end

  test "update saves the field and renders the read-only cell again" do
    song = create_test_song("a.mp3", title: "Before")

    patch song_field_url(song, "title"), params: { song: { title: "After" } }, as: :turbo_stream

    assert_response :success
    assert_equal "After", song.reload.title
    assert_select "turbo-frame#title_song_#{song.id}", text: /After/
    assert_select "input", count: 0
  end

  test "update writes the change to the file" do
    song = create_test_song("a.mp3")

    patch song_field_url(song, "artist"), params: { song: { artist: "Inline Artist" } }, as: :turbo_stream

    assert_equal "Inline Artist", tags_on_disk(song.file_path)[:artist]
  end

  test "each editable field can be updated" do
    song = create_test_song("a.mp3")

    Song::EDITABLE_FIELDS.each do |field|
      value = field.in?(%w[ year disc_number track_number ]) ? "3" : "Value for #{field}"

      patch song_field_url(song, field), params: { song: { field => value } }, as: :turbo_stream

      assert_response :success, "#{field} could not be updated"
    end
  end

  test "clearing a field is allowed" do
    song = create_test_song("a.mp3", genre: "Rock")

    patch song_field_url(song, "genre"), params: { song: { genre: "" } }, as: :turbo_stream

    assert_nil song.reload.genre
  end

  test "an unknown field name is rejected" do
    song = create_test_song("a.mp3")

    get edit_song_field_url(song, "nonsense")

    assert_response :not_found
  end

  test "a field the user may not edit is rejected" do
    song = create_test_song("a.mp3")
    original = song.file_path

    patch song_field_url(song, "file_path"), params: { song: { file_path: "/etc/passwd" } }

    assert_response :not_found
    assert_equal original, song.reload.file_path
  end

  test "a failed write re-renders the input with the error" do
    song = create_test_song("a.mp3")
    File.binwrite(song.file_path, "no longer valid audio")

    patch song_field_url(song, "title"), params: { song: { title: "Doomed" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "input[name='song[title]']"
    assert_select "[role=alert]", text: /Could not write tags/
    assert_equal "Test Song", song.reload.title
  end

  test "the song list renders editable cells as frames" do
    song = create_test_song("a.mp3")

    get songs_url

    %w[ title artist album genre year ].each do |field|
      assert_select "turbo-frame##{field}_song_#{song.id}"
    end
  end

  test "editable cells advertise how to edit them" do
    create_test_song("a.mp3")

    get songs_url

    assert_select "[data-action='dblclick->inline-edit#edit']", minimum: 5
  end
end
