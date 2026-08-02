require "test_helper"

class AlbumsControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper

  setup do
    @song = create_test_song("a.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album_artist: "Neon Fields", album: "Afterglow", track_number: 1,
      album_art_checksum: "abc123", album_art_content_type: "image/png")
    create_test_song("b.mp3", title: "Second", artist: "Neon Fields",
      album_artist: "Neon Fields", album: "Afterglow", track_number: 2)
    create_test_song("c.mp3", title: "Elsewhere", artist: "Other",
      album_artist: "Other", album: "Tidal")
  end

  test "index lists albums" do
    get albums_url

    assert_response :success
    assert_select "h1", text: "Albums"
    assert_select "#albums_count", text: /2 albums/
    assert_select "li", count: 2
  end

  test "index links each album to its page" do
    get albums_url

    assert_select "a[href=?]", album_path(Album.page(1).first)
  end

  # The grid renders 48 covers without loading 48 records, so the URL is built
  # from the id and checksum alone.
  test "index renders covers from the cover song's checksum" do
    get albums_url

    assert_select "img[src=?]", song_album_art_path(song_id: @song.id, v: "abc123")
  end

  test "index searches album and album artist" do
    get albums_url(search: "Tidal")

    assert_response :success
    assert_select "#albums_count", text: /1 album/
    assert_select "li", count: 1
  end

  test "index shows a distinct state when a search matches nothing" do
    get albums_url(search: "nothing matches this")

    assert_select "h2", text: "No albums match your search"
  end

  test "index shows an empty state for an empty library" do
    Song.delete_all

    get albums_url

    assert_select "h2", text: "No albums yet"
  end

  test "index paginates" do
    get albums_url(page: 2, per: 1)

    assert_response :success
  end

  test "show lists the album's tracks in order" do
    get album_url(Album.find(LibraryKey.encode("Neon Fields", "Afterglow")))

    assert_response :success
    assert_select "h1", text: "Afterglow"
    assert_select "tbody tr", count: 2
    assert_select "tbody tr:first-child", text: /Midnight Drive/
  end

  test "show does not list another album's songs" do
    get album_url(Album.find(LibraryKey.encode("Neon Fields", "Afterglow")))

    assert_select "tbody", text: /Elsewhere/, count: 0
  end

  # A compilation is legible because the track artist appears only where it
  # differs from the album artist.
  test "show names the track artist only when it differs from the album artist" do
    create_test_song("d.mp3", title: "Guest Track", artist: "Rozen",
      album_artist: "Various Artists", album: "Harmony of Heroes")
    create_test_song("e.mp3", title: "House Track", artist: "Various Artists",
      album_artist: "Various Artists", album: "Harmony of Heroes")

    get album_url(Album.find(LibraryKey.encode("Various Artists", "Harmony of Heroes")))

    assert_select "tbody tr", text: /Rozen/
    assert_select "tbody tr", text: /House Track.*Various Artists/, count: 0
  end

  # A hand-edited URL is a 404, never a 500.
  test "show 404s for a malformed key" do
    get album_url(id: "not-a-key")

    assert_response :not_found
  end

  test "show 404s for a well-formed key naming no album" do
    get album_url(id: LibraryKey.encode("Nobody", "Nothing"))

    assert_response :not_found
  end

  test "the nav links to albums and stays highlighted on a show page" do
    get albums_url
    assert_select "nav a[href=?][aria-current=page]", albums_path

    get album_url(Album.page(1).first)
    assert_select "nav a[href=?][aria-current=page]", albums_path
  end
end
