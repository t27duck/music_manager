require "test_helper"

class Songs::AlbumArtsControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper

  # A tiny valid GIF. The cover.jpg fixture is byte-identical to the art already
  # embedded in the MP3 fixture, so tests that need *different* art use this.
  GIF = "GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xFF\xFF\xFF!\xF9\x04\x00\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;".b

  setup do
    @song = SongImporter.call(copy_fixture("song.mp3"))
    @cover = File.binread(fixture_file("cover.jpg"))
  end

  test "show serves the embedded image" do
    get song_album_art_url(@song)

    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal @song.album_art, response.body.b
  end

  # Rails hashes the etag value, so assert the contract rather than the literal:
  # different art must produce a different etag.
  test "the etag changes when the art changes" do
    get song_album_art_url(@song)
    before = response.headers["ETag"]

    assert_predicate before, :present?

    @song.update_album_art!(GIF)
    get song_album_art_url(@song)

    assert_not_equal before, response.headers["ETag"]
  end

  test "show returns not modified when the etag matches" do
    get song_album_art_url(@song)
    etag = response.headers["ETag"]

    get song_album_art_url(@song), headers: { "If-None-Match" => etag }

    assert_response :not_modified
  end

  test "show caches hard, since the URL carries the checksum" do
    get song_album_art_url(@song, v: @song.album_art_checksum)

    assert_match(/public/, response.headers["Cache-Control"])
    assert_match(/max-age=\d{7,}/, response.headers["Cache-Control"])
  end

  test "show 404s for a song with no art" do
    song = create_test_song("bare.mp3")

    get song_album_art_url(song)

    assert_response :not_found
  end

  test "show 404s when the file has gone missing" do
    File.delete(@song.file_path)

    get song_album_art_url(@song)

    assert_response :not_found
  end

  test "edit renders the art panel" do
    get edit_song_album_art_url(@song)

    assert_response :success
    assert_select "turbo-frame#album_art_song_#{@song.id}"
    assert_select "input[type=file]"
  end

  test "update embeds the uploaded image" do
    patch song_album_art_url(@song), params: { album_art: fixture_file_upload("cover.jpg", "image/jpeg") },
      as: :turbo_stream

    assert_response :success
    assert_equal Digest::MD5.hexdigest(@cover), @song.reload.album_art_checksum
    assert_equal @cover, @song.album_art
  end

  test "update refreshes the panel, the row and reports success" do
    patch song_album_art_url(@song), params: { album_art: fixture_file_upload("cover.jpg", "image/jpeg") },
      as: :turbo_stream

    assert_select "turbo-stream[action=replace][target=album_art_song_#{@song.id}]"
    assert_select "turbo-stream[action=replace][target=song_#{@song.id}]"
    assert_select "turbo-stream[target=toasts]", text: /Album art updated/
  end

  test "update types the image from its bytes, not the declared content type" do
    # cover.jpg is really a PNG; the browser said jpeg.
    patch song_album_art_url(@song), params: { album_art: fixture_file_upload("cover.jpg", "image/jpeg") },
      as: :turbo_stream

    assert_equal "image/png", @song.reload.album_art_content_type
  end

  test "update rejects a file that is not an image" do
    file = Rack::Test::UploadedFile.new(StringIO.new("not an image"), "text/plain", original_filename: "notes.txt")

    patch song_album_art_url(@song), params: { album_art: file }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /JPEG, PNG or GIF/
  end

  test "update reports a missing file instead of blowing up" do
    patch song_album_art_url(@song), as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Choose an image/
  end

  test "a rejected upload does not refresh the row" do
    patch song_album_art_url(@song), as: :turbo_stream

    assert_select "turbo-stream[target=song_#{@song.id}]", count: 0
    assert_select "turbo-stream[target=toasts]", count: 0
  end

  test "destroy removes the art" do
    delete song_album_art_url(@song), as: :turbo_stream

    assert_response :success
    assert_not_predicate @song.reload, :album_art?
    assert_nil @song.album_art
    assert_select "turbo-stream[target=toasts]", text: /Album art removed/
  end

  test "the song list shows a thumbnail for songs with art" do
    get songs_url

    assert_select "img[src*='album_art']"
    assert_select "img[src*='#{@song.album_art_checksum}']"
  end

  test "the song list shows a placeholder for songs without art" do
    create_test_song("bare.mp3", title: "No Art")

    get songs_url

    assert_select "[title='No album art']"
  end

  test "the edit modal includes the art panel" do
    get edit_song_url(@song)

    assert_select "dialog turbo-frame#album_art_song_#{@song.id}"
    assert_select "dialog input[type=file]"
  end

  test "the remove link only appears when there is art" do
    get edit_song_url(@song)
    assert_select "a", text: "Remove art"

    bare = create_test_song("bare.mp3")
    get edit_song_url(bare)
    assert_select "a", text: "Remove art", count: 0
  end
end
