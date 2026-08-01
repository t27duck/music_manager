require "test_helper"

class SongImporterTest < ActiveSupport::TestCase
  include LibraryTestHelper

  test "creates a song from an MP3 on disk" do
    path = copy_fixture("Artist/Album/song.mp3")

    song = SongImporter.call(path)

    assert_predicate song, :persisted?
    assert_equal path, song.file_path
    assert_equal "Test Song One", song.title
    assert_equal File.size(path), song.file_size
    assert_operator song.duration, :>, 0
    assert_predicate song.last_seen_at, :present?
  end

  test "defaults the title to the filename without its extension" do
    path = copy_fixture("Some Untitled Track.mp3")
    Mp3Info.open(path) { |mp3| mp3.tag2["TIT2"] = nil }

    song = SongImporter.call(path)

    assert_equal "Some Untitled Track", song.title
  end

  test "updates the existing song instead of creating a duplicate" do
    path = copy_fixture("song.mp3")
    original = SongImporter.call(path)
    Mp3File.new(path).write_attributes(title: "Retagged Outside The App")

    reimported = assert_no_difference -> { Song.count } do
      SongImporter.call(path)
    end

    assert_equal original.id, reimported.id
    assert_equal "Retagged Outside The App", reimported.title
  end

  test "does not write tags back to the file it just read" do
    path = copy_fixture("song.mp3")
    original_mtime = File.mtime(path)

    SongImporter.call(path)

    assert_equal original_mtime, File.mtime(path)
  end

  test "records embedded album art" do
    song = SongImporter.call(copy_fixture("song.mp3"))

    assert_predicate song, :album_art?
    assert_equal "image/png", song.album_art_content_type
  end

  test "raises Mp3File::Error for an unreadable file so the caller can skip it" do
    path = File.join(@temp_dir, "broken.mp3")
    File.binwrite(path, "not audio")

    assert_raises(Mp3File::Error) { SongImporter.call(path) }
    assert_equal 0, songs_in_temp_dir.count
  end

  test "normalizes the path so the same file is never imported twice" do
    path = copy_fixture("Artist/song.mp3")
    SongImporter.call(path)

    assert_no_difference -> { Song.count } do
      SongImporter.call(File.join(@temp_dir, "Artist", "..", "Artist", "song.mp3"))
    end
  end
end
