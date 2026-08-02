require "test_helper"

class SongSearchTest < ActiveSupport::TestCase
  include LibraryTestHelper

  test "file_path_contains matches a substring of the path" do
    match = create_test_song("Artist/Album/wanted.mp3")
    create_test_song("Artist/Album/other.mp3")

    assert_equal [ match.id ], songs_in_temp_dir.file_path_contains("wanted").pluck(:id)
  end

  # The reason these are scopes rather than Ransack's built-in `cont`.
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

  test "title_contains treats an underscore literally, not as a wildcard" do
    literal = create_test_song("a.mp3", title: "my_song")
    create_test_song("b.mp3", title: "myXsong")

    assert_equal [ literal.id ], songs_in_temp_dir.title_contains("my_song").pluck(:id)
  end

  test "album_artist_contains treats an underscore literally, not as a wildcard" do
    literal = create_test_song("a.mp3", album_artist: "my_label")
    create_test_song("b.mp3", album_artist: "myXlabel")

    assert_equal [ literal.id ], songs_in_temp_dir.album_artist_contains("my_label").pluck(:id)
  end

  test "the global search looks through the album artist too" do
    wanted = create_test_song("a.mp3", artist: "Rozen", album_artist: "Various Artists")
    create_test_song("b.mp3", artist: "Someone", album_artist: "Someone")

    assert_equal [ wanted.id ], songs_in_temp_dir.text_contains("Various").pluck(:id)
  end

  test "text_contains treats an underscore literally, not as a wildcard" do
    literal = create_test_song("a.mp3", album: "my_album")
    create_test_song("b.mp3", album: "myXalbum")

    assert_equal [ literal.id ], songs_in_temp_dir.text_contains("my_album").pluck(:id)
  end

  # Ransack coerces a scope's argument through its TRUE_VALUES/FALSE_VALUES list
  # unless the scope opts out. Before it did, "t" raised ArgumentError and "0"
  # silently dropped the filter -- both reachable by typing one character into
  # the search box.
  test "a search for a single value Ransack would read as a boolean still filters" do
    wanted = create_test_song("t.mp3", title: "t", artist: "t", album: "t", genre: "t")
    create_test_song("zebra.mp3", title: "Zebra", artist: "Zebra", album: "Zebra", genre: "Zebra")

    # file_path_contains is left out: every file is under a temp directory whose
    # own path contains a "t", so "t" legitimately matches all of them. It gets
    # its own case below.
    (Song::FILTER_SCOPES - [ "missing_metadata", "file_path_contains" ]).each do |scope|
      found = songs_in_temp_dir.ransack(scope => "t").result

      assert_equal [ wanted.id ], found.pluck(:id), "#{scope} did not filter on \"t\""
    end

    # This used to raise ArgumentError before the scope opted out of coercion.
    assert_equal 2, songs_in_temp_dir.ransack(file_path_contains: "t").result.count
  end

  test "a search for \"0\" filters rather than being read as false" do
    wanted = create_test_song("a.mp3", artist: "0")
    create_test_song("b.mp3", artist: "Someone")

    assert_equal [ wanted.id ], songs_in_temp_dir.ransack(artist_contains: "0").result.pluck(:id)
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
      .ransack(text_contains: "Needle").result

    assert_equal [ by_title, by_artist, by_album, by_genre ].map(&:id).sort, found.pluck(:id).sort
  end

  test "ransack search is case-insensitive" do
    create_test_song("a.mp3", title: "Midnight Drive")

    found = songs_in_temp_dir.ransack(text_contains: "midnight").result

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

    found = songs_in_temp_dir.ransack(artist_contains: "Alpha", genre_contains: "Jazz").result

    assert_equal [ wanted.id ], found.pluck(:id)
  end
end
