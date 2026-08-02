require "test_helper"

class SongTest < ActiveSupport::TestCase
  include LibraryTestHelper

  test "requires a file path" do
    song = Song.new(title: "No Path")

    assert_not song.valid?
    assert_includes song.errors.attribute_names, :file_path
  end

  test "requires a unique file path" do
    existing = create_test_song("song.mp3")
    duplicate = Song.new(file_path: existing.file_path, title: "Copy")

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :file_path
  end

  test "stores blank metadata as nil so missing-metadata filters can use IS NULL" do
    song = create_test_song("song.mp3", artist: "   ", album: "")

    assert_nil song.artist
    assert_nil song.album
  end

  # About a tenth of real files carry no TPE2. Without a fallback those songs
  # would collect in one nameless album.
  test "the album artist falls back to the artist when the file has no TPE2" do
    song = create_test_song("a.mp3", artist: "Neon Fields", album_artist: nil)

    assert_equal "Neon Fields", song.album_artist
  end

  test "an explicit album artist is kept" do
    song = create_test_song("a.mp3", artist: "Rozen", album_artist: "Various Artists")

    assert_equal "Various Artists", song.album_artist
  end

  test "clearing the album artist falls back to the artist again" do
    song = create_test_song("a.mp3", artist: "Neon Fields", album_artist: "Various Artists")

    song.update!(album_artist: "")

    assert_equal "Neon Fields", song.reload.album_artist
  end

  test "the album artist is written through to the file" do
    song = create_test_song("a.mp3", artist: "Rozen")

    song.update!(album_artist: "Various Artists")

    assert_equal "Various Artists", tags_on_disk(song.file_path)[:album_artist]
  end

  test "writes changed tags through to the file" do
    song = create_test_song("song.mp3")

    song.update!(title: "Written Through", artist: "New Artist", year: 2001)

    tags = tags_on_disk(song.file_path)
    assert_equal "Written Through", tags[:title]
    assert_equal "New Artist", tags[:artist]
    assert_equal 2001, tags[:year]
  end

  test "writes every tag attribute, not only the changed one" do
    song = create_test_song("song.mp3", artist: "Original Artist")

    song.update!(title: "Only Title Changed")

    tags = tags_on_disk(song.file_path)
    assert_equal "Only Title Changed", tags[:title]
    assert_equal "Original Artist", tags[:artist]
  end

  test "does not touch the file when no tag attribute changed" do
    song = create_test_song("song.mp3")
    original_mtime = File.mtime(song.file_path)

    song.update!(last_seen_at: Time.current)

    assert_equal original_mtime, File.mtime(song.file_path)
  end

  test "rolls back the record when the file cannot be written" do
    song = create_test_song("song.mp3")
    File.binwrite(song.file_path, "no longer a valid mp3")

    assert_not song.update(title: "Doomed")

    assert_equal "Test Song", song.reload.title
    assert_includes song.errors[:base].join, "Could not write tags"
  end

  test "skip_tag_write bypasses the write-through callback" do
    song = create_test_song("song.mp3")
    original_mtime = File.mtime(song.file_path)

    song.skip_tag_write = true
    song.update!(title: "Database Only")

    assert_equal original_mtime, File.mtime(song.file_path)
    assert_equal "Test Song One", tags_on_disk(song.file_path)[:title]
  end

  test "exposes the filename and library-relative path" do
    song = create_test_song("Artist/Album/track.mp3")

    assert_equal "track.mp3", song.filename
    assert_equal "Artist/Album/track.mp3", song.relative_path
  end

  test "album_art? reflects the checksum" do
    song = create_test_song("song.mp3")

    assert_not_predicate song, :album_art?

    song.update!(album_art_checksum: "abc123")
    assert_predicate song, :album_art?
  end

  test "ordered sorts by artist, album, disc, track" do
    second = create_test_song("b.mp3", artist: "A", album: "A", disc_number: 1, track_number: 2)
    first = create_test_song("a.mp3", artist: "A", album: "A", disc_number: 1, track_number: 1)
    third = create_test_song("c.mp3", artist: "B", album: "A", disc_number: 1, track_number: 1)

    assert_equal [ first, second, third ], songs_in_temp_dir.ordered.to_a
  end

  test "destroy_with_file! removes the record and the file" do
    song = create_test_song("song.mp3")
    path = song.file_path

    song.destroy_with_file!

    assert_not Song.exists?(song.id)
    assert_not File.exist?(path)
  end

  test "destroy_with_file! succeeds when the file is already gone" do
    song = create_test_song("song.mp3")
    File.delete(song.file_path)

    song.destroy_with_file!

    assert_not Song.exists?(song.id)
  end

  test "destroy_with_file! keeps the record when the file cannot be deleted" do
    song = create_test_song("locked/song.mp3")
    directory = File.dirname(song.file_path)
    FileUtils.chmod(0o500, directory)

    assert_raises(SystemCallError) { song.destroy_with_file! }

    assert Song.exists?(song.id), "the record was destroyed even though its file survived"
  ensure
    FileUtils.chmod(0o700, directory) if directory
  end
end
