require "test_helper"

class ArtistTest < ActiveSupport::TestCase
  include LibraryTestHelper

  def artist_named(name) = Artist.page(1).find { |artist| artist.name == name }

  test "groups songs by album artist" do
    create_test_song("a.mp3", album_artist: "Neon Fields", album: "One")
    create_test_song("b.mp3", album_artist: "Neon Fields", album: "Two")
    create_test_song("c.mp3", album_artist: "Other", album: "Three")

    assert_equal 2, Artist.page(1).total_count
    assert_equal 2, artist_named("Neon Fields").songs_count
  end

  test "counts distinct albums" do
    create_test_song("a.mp3", album_artist: "X", album: "One")
    create_test_song("b.mp3", album_artist: "X", album: "One")
    create_test_song("c.mp3", album_artist: "X", album: "Two")

    assert_equal 2, artist_named("X").albums_count
    assert_equal 3, artist_named("X").songs_count
  end

  # Grouping on album_artist rather than artist is what makes a compilation one
  # entry instead of one per guest performer.
  test "a compilation's guest artists do not each become an artist" do
    3.times do |i|
      create_test_song("#{i}.mp3", artist: "Guest #{i}",
        album_artist: "Various Artists", album: "Harmony of Heroes")
    end

    assert_equal 1, Artist.page(1).total_count
    assert_equal "Various Artists", Artist.page(1).first.name
  end

  test "searches by name, escaping wildcards" do
    create_test_song("a.mp3", album_artist: "my_band", album: "X")
    create_test_song("b.mp3", album_artist: "myXband", album: "Y")

    assert_equal [ "my_band" ], Artist.page(1, search: "my_band").map(&:name)
  end

  test "find round-trips to_param" do
    create_test_song("a.mp3", album_artist: "Neon Fields", album: "One")

    artist = artist_named("Neon Fields")

    assert_equal "Neon Fields", Artist.find(artist.to_param).name
  end

  test "find raises for a well-formed key naming no artist" do
    assert_raises(ActiveRecord::RecordNotFound) { Artist.find(LibraryKey.encode("Nobody")) }
  end

  test "albums returns only that artist's albums" do
    create_test_song("a.mp3", album_artist: "Wanted", album: "One")
    create_test_song("b.mp3", album_artist: "Wanted", album: "Two")
    create_test_song("c.mp3", album_artist: "Other", album: "Three")

    assert_equal %w[ One Two ], artist_named("Wanted").albums.map(&:name)
  end

  test "songs with no album artist group together and still have a key" do
    create_test_song("a.mp3", artist: nil, album_artist: nil, album: "X")

    artist = Artist.page(1).first
    assert_equal "Unknown artist", artist.display_name
    assert_equal 1, Artist.find(artist.to_param).songs_count
  end

  test "carries a cover from one of its songs" do
    song = create_test_song("a.mp3", album_artist: "X", album: "Y",
      album_art_checksum: "abc123", album_art_content_type: "image/png")

    assert_equal song.id, artist_named("X").cover_song_id
    assert_equal "abc123", artist_named("X").cover_checksum
  end

  test "paginates" do
    3.times { |i| create_test_song("#{i}.mp3", album_artist: "Artist #{i}", album: "X") }

    page = Artist.page(2, per: 2)

    assert_equal 3, page.total_count
    assert_equal 1, page.size
  end
end
