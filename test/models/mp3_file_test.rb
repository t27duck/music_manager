require "test_helper"

class Mp3FileTest < ActiveSupport::TestCase
  include LibraryTestHelper

  test "reads tags from a fixture" do
    attributes = Mp3File.new(copy_fixture("song.mp3")).attributes

    assert_equal "Test Song One", attributes[:title]
    assert_operator attributes[:duration], :>, 0
    assert_operator attributes[:bitrate], :>, 0
  end

  test "reports embedded album art" do
    attributes = Mp3File.new(copy_fixture("song.mp3")).attributes

    assert_equal 32, attributes[:album_art_checksum].length
    assert_equal "image/png", attributes[:album_art_content_type]
  end

  test "album art returns the raw picture bytes" do
    art = Mp3File.new(copy_fixture("song.mp3")).album_art

    assert_predicate art, :present?
    assert_equal "image/png", Mp3File.image_content_type(art)
  end

  test "round-trips written tags" do
    path = copy_fixture("song.mp3")

    Mp3File.new(path).write_attributes(
      title: "New Title", artist: "New Artist", album: "New Album",
      album_artist: "New Album Artist",
      genre: "Jazz", year: 1999, track_number: 3, disc_number: 2
    )
    attributes = Mp3File.new(path).attributes

    assert_equal "New Title", attributes[:title]
    assert_equal "New Artist", attributes[:artist]
    assert_equal "New Album Artist", attributes[:album_artist]
    assert_equal "New Album", attributes[:album]
    assert_equal "Jazz", attributes[:genre]
    assert_equal 1999, attributes[:year]
    assert_equal 3, attributes[:track_number]
    assert_equal 2, attributes[:disc_number]
  end

  # TPE2 has no generic key in ruby-mp3info's mapping, so it is written straight
  # to the frame -- the same treatment TPOS gets.
  test "reads the album artist from the TPE2 frame" do
    path = copy_fixture("song.mp3")
    Mp3Info.open(path) { |mp3| mp3.tag2["TPE2"] = "Various Artists" }

    assert_equal "Various Artists", Mp3File.new(path).attributes[:album_artist]
  end

  test "a file with no TPE2 reads a nil album artist" do
    path = copy_fixture("song.mp3")

    assert_nil Mp3File.new(path).attributes[:album_artist]
  end

  # The frame has no ID3v1 counterpart, so unlike the generic keys a nil is
  # enough -- but only because ID3v2#to_bin skips nil values when it rebuilds
  # the tag. Assert against the file, since nothing else would catch a regression.
  test "clearing the album artist deletes the TPE2 frame" do
    path = copy_fixture("song.mp3")
    Mp3File.new(path).write_attributes(album_artist: "Various Artists")

    Mp3File.new(path).write_attributes(album_artist: nil)

    Mp3Info.open(path) { |mp3| assert_nil mp3.tag2["TPE2"] }
    assert_nil Mp3File.new(path).attributes[:album_artist]
  end

  test "writing tags preserves embedded album art" do
    path = copy_fixture("song.mp3")
    original_checksum = Mp3File.new(path).attributes[:album_art_checksum]

    Mp3File.new(path).write_attributes(title: "Rewritten")

    assert_equal original_checksum, Mp3File.new(path).attributes[:album_art_checksum]
  end

  test "writes both ID3v1 and ID3v2 tags" do
    path = copy_fixture("song.mp3")

    Mp3File.new(path).write_attributes(title: "Both Tags", artist: "Someone")

    Mp3Info.open(path) do |mp3|
      assert mp3.hastag1?, "expected an ID3v1 tag"
      assert mp3.hastag2?, "expected an ID3v2 tag"
      assert_equal "Both Tags", mp3.tag1["title"]
      assert_equal "Both Tags", mp3.tag2["TIT2"]
    end
  end

  test "only writes the attributes it is given" do
    path = copy_fixture("song.mp3")
    Mp3File.new(path).write_attributes(title: "Keep Me", artist: "Keep Me Too")

    Mp3File.new(path).write_attributes(album: "Only This Changed")

    attributes = Mp3File.new(path).attributes
    assert_equal "Keep Me", attributes[:title]
    assert_equal "Keep Me Too", attributes[:artist]
    assert_equal "Only This Changed", attributes[:album]
  end

  test "clears a tag when given a blank value" do
    path = copy_fixture("song.mp3")
    Mp3File.new(path).write_attributes(artist: "Temporary")

    Mp3File.new(path).write_attributes(artist: "")

    assert_nil Mp3File.new(path).attributes[:artist]
  end

  test "strips NUL bytes left over from fixed-width ID3v1 fields" do
    path = copy_fixture("song.mp3")
    Mp3Info.open(path) { |mp3| mp3.tag2["TIT2"] = "Padded Title\u0000\u0000" }

    assert_equal "Padded Title", Mp3File.new(path).attributes[:title]
  end

  # Sanitization is tested directly rather than through a file: ruby-mp3info
  # refuses to encode invalid bytes on write and normalizes them on read, so a
  # file-based test would pass without ever exercising the scrub path.
  test "sanitize_string scrubs invalid UTF-8" do
    sanitized = Mp3File.sanitize_string("Caf\xC3 invalid".b)

    assert_predicate sanitized, :valid_encoding?
    assert_equal Encoding::UTF_8, sanitized.encoding
    assert_includes sanitized, "invalid"
  end

  test "sanitize_string removes NUL bytes and surrounding whitespace" do
    assert_equal "Padded Title", Mp3File.sanitize_string("  Padded Title\u0000\u0000 ")
  end

  test "sanitize_string returns nil for blank values" do
    assert_nil Mp3File.sanitize_string(nil)
    assert_nil Mp3File.sanitize_string("   ")
    assert_nil Mp3File.sanitize_string("\u0000")
  end

  test "parses slashed track and disc numbers" do
    path = copy_fixture("song.mp3")
    Mp3Info.open(path) do |mp3|
      mp3.tag2["TRCK"] = "3/12"
      mp3.tag2["TPOS"] = "1/2"
    end

    attributes = Mp3File.new(path).attributes

    assert_equal 3, attributes[:track_number]
    assert_equal 1, attributes[:disc_number]
  end

  test "parses a full date into a year" do
    path = copy_fixture("song.mp3")
    Mp3Info.open(path) { |mp3| mp3.tag2["TYER"] = "1999-01-01" }

    assert_equal 1999, Mp3File.new(path).attributes[:year]
  end

  test "raises Mp3File::Error for a missing file" do
    error = assert_raises(Mp3File::Error) do
      Mp3File.new(File.join(@temp_dir, "nope.mp3")).attributes
    end

    assert_match(/not found/i, error.message)
  end

  test "raises Mp3File::Error for a file that is not an MP3" do
    path = File.join(@temp_dir, "broken.mp3")
    File.binwrite(path, "this is not audio")

    assert_raises(Mp3File::Error) { Mp3File.new(path).attributes }
  end

  # Content type comes from magic bytes, never the filename: the cover.jpg
  # fixture is in fact a PNG, which is exactly the case this guards against.
  test "detects image content types from magic bytes" do
    assert_equal "image/png", Mp3File.image_content_type("\x89PNG\r\n".b)
    assert_equal "image/gif", Mp3File.image_content_type("GIF89a".b)
    assert_equal "image/jpeg", Mp3File.image_content_type("\xFF\xD8\xFF\xE0".b)
    assert_equal "application/octet-stream", Mp3File.image_content_type("nonsense".b)
  end

  test "ignores the extension when typing the cover fixture" do
    assert_equal "image/png", Mp3File.image_content_type(File.binread(fixture_file("cover.jpg"), 16))
  end
end
