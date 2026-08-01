require "test_helper"

class SongAlbumArtTest < ActiveSupport::TestCase
  include LibraryTestHelper

  # A tiny valid GIF, so tests can use a second image type without a fixture.
  GIF = "GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xFF\xFF\xFF!\xF9\x04\x00\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;".b

  setup do
    @song = create_test_song("song.mp3")
    @cover = File.binread(fixture_file("cover.jpg"))
  end

  test "reads the art embedded in the fixture" do
    art = @song.album_art

    assert_predicate art, :present?
    assert_equal "image/png", Mp3File.image_content_type(art)
  end

  test "update_album_art! embeds the image and records what it is" do
    @song.update_album_art!(@cover)

    assert_equal Digest::MD5.hexdigest(@cover), @song.album_art_checksum
    assert_equal "image/png", @song.album_art_content_type
    assert_equal @cover, @song.album_art
  end

  test "update_album_art! replaces existing art rather than adding a second image" do
    @song.update_album_art!(@cover)
    @song.update_album_art!(GIF)

    assert_equal GIF, @song.album_art
    assert_equal "image/gif", @song.album_art_content_type
  end

  test "update_album_art! types the image from its bytes, not its extension" do
    # The cover.jpg fixture is really a PNG.
    @song.update_album_art!(@cover)

    assert_equal "image/png", @song.album_art_content_type
  end

  test "update_album_art! leaves the other tags alone" do
    @song.update_album_art!(@cover)

    assert_equal "Test Song One", tags_on_disk(@song.file_path)[:title]
  end

  test "remove_album_art! clears the image and the recorded metadata" do
    @song.update_album_art!(@cover)

    @song.remove_album_art!

    assert_nil @song.album_art
    assert_nil @song.album_art_checksum
    assert_nil @song.album_art_content_type
    assert_not_predicate @song, :album_art?
  end

  test "remove_album_art! leaves the other tags alone" do
    @song.remove_album_art!

    assert_equal "Test Song One", tags_on_disk(@song.file_path)[:title]
  end

  test "rejects an empty image" do
    error = assert_raises(Song::InvalidAlbumArt) { @song.update_album_art!("") }

    assert_match(/empty/i, error.message)
  end

  test "rejects a file that is not an image" do
    error = assert_raises(Song::InvalidAlbumArt) { @song.update_album_art!("just some text") }

    assert_match(/JPEG, PNG or GIF/, error.message)
  end

  test "rejects an image larger than the limit" do
    oversized = "\x89PNG\r\n".b + ("x" * Song::MAX_ALBUM_ART_BYTES)

    error = assert_raises(Song::InvalidAlbumArt) { @song.update_album_art!(oversized) }

    assert_match(/or smaller/, error.message)
  end

  test "a rejected image leaves the existing art untouched" do
    @song.update_album_art!(@cover)
    before = File.mtime(@song.file_path)

    assert_raises(Song::InvalidAlbumArt) { @song.update_album_art!("not an image") }

    assert_equal Digest::MD5.hexdigest(@cover), @song.reload.album_art_checksum
    assert_equal @cover, @song.album_art
    assert_equal before, File.mtime(@song.file_path)
  end

  test "accepts a frozen string" do
    @song.update_album_art!(GIF.freeze)

    assert_equal GIF, @song.album_art
  end

  test "the importer records art already embedded in a file" do
    song = SongImporter.call(copy_fixture("imported.mp3"))

    assert_predicate song, :album_art?
    assert_equal "image/png", song.album_art_content_type
  end
end
