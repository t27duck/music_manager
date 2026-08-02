require "test_helper"

class AlbumTest < ActiveSupport::TestCase
  include LibraryTestHelper

  def album_named(name) = Album.page(1).find { |album| album.name == name }

  test "groups songs by album artist and album" do
    create_test_song("a.mp3", album_artist: "Neon Fields", album: "Afterglow")
    create_test_song("b.mp3", album_artist: "Neon Fields", album: "Afterglow")
    create_test_song("c.mp3", album_artist: "Neon Fields", album: "Other")

    assert_equal 2, Album.page(1).total_count
    assert_equal 2, album_named("Afterglow").songs_count
  end

  # The whole reason album_artist exists: a compilation is one album, not one
  # album per track artist.
  test "a compilation with many track artists is one album" do
    3.times do |i|
      create_test_song("#{i}.mp3", artist: "Artist #{i}",
        album_artist: "Various Artists", album: "Harmony of Heroes")
    end

    assert_equal 1, Album.page(1).total_count
    assert_equal 3, album_named("Harmony of Heroes").songs_count
    assert_equal "Various Artists", album_named("Harmony of Heroes").artist
  end

  test "two artists with the same album name are two albums" do
    create_test_song("a.mp3", album_artist: "One", album: "Greatest Hits")
    create_test_song("b.mp3", album_artist: "Two", album: "Greatest Hits")

    assert_equal 2, Album.page(1).total_count
  end

  test "aggregates duration and years" do
    create_test_song("a.mp3", album_artist: "X", album: "Y", duration: 100, year: 1996)
    create_test_song("b.mp3", album_artist: "X", album: "Y", duration: 200, year: 1999)

    album = album_named("Y")
    assert_equal 300, album.total_duration
    assert_equal "1996–1999", album.years
  end

  test "a single year is not rendered as a range" do
    create_test_song("a.mp3", album_artist: "X", album: "Y", year: 1996)

    assert_equal "1996", album_named("Y").years
  end

  test "years is nil when nothing is tagged" do
    create_test_song("a.mp3", album_artist: "X", album: "Y", year: nil)

    assert_nil album_named("Y").years
  end

  # The checksum is fetched in a second query keyed on cover_song_id, so this is
  # what would catch it being paired with the wrong row.
  test "carries a cover from one of its songs" do
    song = create_test_song("a.mp3", album_artist: "X", album: "Y",
      album_art_checksum: "abc123", album_art_content_type: "image/png")
    create_test_song("b.mp3", album_artist: "X", album: "Y")

    album = album_named("Y")
    assert_equal song.id, album.cover_song_id
    assert_equal "abc123", album.cover_checksum
  end

  test "an album with no art carries no cover checksum" do
    create_test_song("a.mp3", album_artist: "X", album: "Y")

    assert_nil album_named("Y").cover_checksum
  end

  test "searches album and album artist, escaping wildcards" do
    create_test_song("a.mp3", album_artist: "Neon Fields", album: "my_album")
    create_test_song("b.mp3", album_artist: "Other", album: "myXalbum")

    assert_equal [ "my_album" ], Album.page(1, search: "my_album").map(&:name)
    assert_equal [ "my_album" ], Album.page(1, search: "Neon").map(&:name)
  end

  test "find round-trips to_param" do
    create_test_song("a.mp3", album_artist: "Various Artists", album: "Harmony of Heroes")

    album = album_named("Harmony of Heroes")

    assert_equal album.name, Album.find(album.to_param).name
    assert_equal album.artist, Album.find(album.to_param).artist
  end

  test "find raises for a well-formed key naming no album" do
    assert_raises(ActiveRecord::RecordNotFound) { Album.find(LibraryKey.encode("Nobody", "Nothing")) }
  end

  test "songs are ordered by disc, then track, then title" do
    create_test_song("c.mp3", album_artist: "X", album: "Y", disc_number: 1, track_number: 2, title: "Second")
    create_test_song("a.mp3", album_artist: "X", album: "Y", disc_number: 1, track_number: 1, title: "First")
    create_test_song("d.mp3", album_artist: "X", album: "Y", disc_number: 2, track_number: 1, title: "Third")

    assert_equal %w[ First Second Third ], album_named("Y").songs.pluck(:title)
  end

  # A song with no album still needs somewhere to live and a URL that works.
  test "songs with no album group together and still have a key" do
    create_test_song("a.mp3", album_artist: "X", album: nil)
    create_test_song("b.mp3", album_artist: "X", album: nil)

    album = Album.page(1).first
    assert_equal 2, album.songs_count
    assert_equal "Unknown album", album.display_name
    assert_equal album.songs_count, Album.find(album.to_param).songs_count
  end

  test "paginates" do
    3.times { |i| create_test_song("#{i}.mp3", album_artist: "X", album: "Album #{i}") }

    page = Album.page(2, per: 2)

    assert_equal 3, page.total_count
    assert_equal 2, page.total_pages
    assert_equal 1, page.size
  end

  test "for_artist returns only that artist's albums" do
    create_test_song("a.mp3", album_artist: "Wanted", album: "One")
    create_test_song("b.mp3", album_artist: "Wanted", album: "Two")
    create_test_song("c.mp3", album_artist: "Other", album: "Three")

    assert_equal %w[ One Two ], Album.for_artist("Wanted").map(&:name)
  end
end
