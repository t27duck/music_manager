require "test_helper"

class SongSearchTest < ActiveSupport::TestCase
  include LibraryTestHelper

  test "file_path_contains matches a substring of the path" do
    match = create_test_song("Artist/Album/wanted.mp3")
    create_test_song("Artist/Album/other.mp3")

    assert_equal [ match.id ], songs_in_temp_dir.file_path_contains("wanted").pluck(:id)
  end

  # The reason this scope exists rather than Ransack's built-in `cont`.
  test "file_path_contains treats an underscore literally, not as a wildcard" do
    literal = create_test_song("my_song.mp3")
    create_test_song("myXsong.mp3")

    assert_equal [ literal.id ], songs_in_temp_dir.file_path_contains("my_song").pluck(:id)
  end

  test "file_path_contains treats a percent sign literally" do
    literal = create_test_song("100%25 Hits/track.mp3")
    create_test_song("other/track.mp3")

    assert_equal [ literal.id ], songs_in_temp_dir.file_path_contains("100%25 Hits").pluck(:id)
  end

  test "file_path_contains with a blank value filters nothing" do
    create_test_song("a.mp3")
    create_test_song("b.mp3")

    assert_equal 2, songs_in_temp_dir.file_path_contains("").count
  end

  test "missing_metadata finds songs with no artist" do
    missing = create_test_song("a.mp3", artist: nil)
    create_test_song("b.mp3", artist: "Present")

    assert_equal [ missing.id ], songs_in_temp_dir.missing_metadata("artist").pluck(:id)
  end

  test "missing_metadata treats an empty string as missing" do
    song = create_test_song("a.mp3")
    song.update_column(:genre, "")

    assert_equal [ song.id ], songs_in_temp_dir.missing_metadata("genre").pluck(:id)
  end

  test "missing_metadata finds songs with no year" do
    missing = create_test_song("a.mp3", year: nil)
    create_test_song("b.mp3", year: 1999)

    assert_equal [ missing.id ], songs_in_temp_dir.missing_metadata("year").pluck(:id)
  end

  test "missing_metadata ignores a field that is not allow-listed" do
    create_test_song("a.mp3")

    assert_equal 1, songs_in_temp_dir.missing_metadata("file_path").count
    assert_equal 1, songs_in_temp_dir.missing_metadata("nonsense").count
  end

  test "ransack searches title, artist, album and genre at once" do
    by_title = create_test_song("a.mp3", title: "Needle", artist: "X", album: "X", genre: "X")
    by_artist = create_test_song("b.mp3", title: "X", artist: "Needle", album: "X", genre: "X")
    by_album = create_test_song("c.mp3", title: "X", artist: "X", album: "Needle", genre: "X")
    by_genre = create_test_song("d.mp3", title: "X", artist: "X", album: "X", genre: "Needle")
    create_test_song("e.mp3", title: "X", artist: "X", album: "X", genre: "X")

    found = songs_in_temp_dir
      .ransack(title_or_artist_or_album_or_genre_cont: "Needle").result

    assert_equal [ by_title, by_artist, by_album, by_genre ].map(&:id).sort, found.pluck(:id).sort
  end

  test "ransack search is case-insensitive" do
    create_test_song("a.mp3", title: "Midnight Drive")

    found = songs_in_temp_dir.ransack(title_or_artist_or_album_or_genre_cont: "midnight").result

    assert_equal 1, found.count
  end

  test "ransack does not expose file_path as a searchable attribute" do
    assert_not_includes Song.ransackable_attributes, "file_path"
  end

  test "file_path is still sortable" do
    assert_includes Song.ransortable_attributes, "file_path"
  end

  test "combining filters narrows the result" do
    create_test_song("a.mp3", artist: "Alpha", genre: "Rock")
    wanted = create_test_song("b.mp3", artist: "Alpha", genre: "Jazz")
    create_test_song("c.mp3", artist: "Beta", genre: "Jazz")

    found = songs_in_temp_dir.ransack(artist_cont: "Alpha", genre_cont: "Jazz").result

    assert_equal [ wanted.id ], found.pluck(:id)
  end
end
