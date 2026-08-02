require "test_helper"

class ArtistsControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper

  setup do
    create_test_song("a.mp3", title: "One", artist: "Neon Fields",
      album_artist: "Neon Fields", album: "Afterglow")
    create_test_song("b.mp3", title: "Two", artist: "Neon Fields",
      album_artist: "Neon Fields", album: "Tidal")
    create_test_song("c.mp3", title: "Guest", artist: "Rozen",
      album_artist: "Various Artists", album: "Harmony of Heroes")
  end

  def artist_for(name) = Artist.find(LibraryKey.encode(name))

  test "index lists artists" do
    get artists_url

    assert_response :success
    assert_select "h1", text: "Artists"
    assert_select "#artists_count", text: /2 artists/
    assert_select "li", count: 2
  end

  test "index counts albums and songs per artist" do
    get artists_url

    assert_select "li", text: /Neon Fields.*2 albums.*2 songs/
  end

  test "index searches by name" do
    get artists_url(search: "Various")

    assert_select "#artists_count", text: /1 artist/
    assert_select "li", count: 1
  end

  test "index shows a distinct state when a search matches nothing" do
    get artists_url(search: "nothing matches this")

    assert_select "h2", text: "No artists match your search"
  end

  test "index shows an empty state for an empty library" do
    Song.delete_all

    get artists_url

    assert_select "h2", text: "No artists yet"
  end

  test "show lists the artist's albums" do
    get artist_url(artist_for("Neon Fields"))

    assert_response :success
    assert_select "h1", text: "Neon Fields"
    assert_select "li", count: 2
    assert_select "li", text: /Afterglow/
    assert_select "li", text: /Tidal/
  end

  test "show does not list another artist's albums" do
    get artist_url(artist_for("Neon Fields"))

    assert_select "li", text: /Harmony of Heroes/, count: 0
  end

  test "show 404s for a malformed key" do
    get artist_url(id: "not-a-key")

    assert_response :not_found
  end

  test "show 404s for a well-formed key naming no artist" do
    get artist_url(id: LibraryKey.encode("Nobody"))

    assert_response :not_found
  end

  test "an album page links through to its artist" do
    get album_url(Album.find(LibraryKey.encode("Neon Fields", "Afterglow")))

    assert_select "a[href=?]", artist_path(LibraryKey.encode("Neon Fields")), text: "Neon Fields"
  end

  test "the nav links to artists and stays highlighted on a show page" do
    get artists_url
    assert_select "nav a[href=?][aria-current=page]", artists_path

    get artist_url(artist_for("Neon Fields"))
    assert_select "nav a[href=?][aria-current=page]", artists_path
  end
end
