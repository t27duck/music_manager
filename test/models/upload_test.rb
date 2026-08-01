require "test_helper"

class UploadTest < ActiveSupport::TestCase
  include LibraryTestHelper

  def uploaded(name = "song.mp3", fixture: LibraryTestHelper::FIXTURE_MP3)
    Rack::Test::UploadedFile.new(fixture_file(fixture), "audio/mpeg", original_filename: name)
  end

  def new_dir(*parts) = File.join(@temp_dir, Upload::DESTINATION, *parts)

  test "saves the file into _NEW and imports it" do
    song = Upload.new(file: uploaded).save!

    assert_equal new_dir("song.mp3"), song.file_path
    assert File.exist?(song.file_path)
    assert_equal "Test Song One", song.title
  end

  test "keeps the folder structure it was given" do
    song = Upload.new(file: uploaded, relative_path: "Artist/Album/track.mp3").save!

    assert_equal new_dir("Artist/Album/track.mp3"), song.file_path
  end

  test "falls back to the uploaded filename when no path is given" do
    upload = Upload.new(file: uploaded("bare.mp3"))

    assert_equal "bare.mp3", upload.filename
  end

  test "re-uploading the same path updates the existing song" do
    Upload.new(file: uploaded, relative_path: "a/song.mp3").save!

    assert_no_difference -> { Song.count } do
      Upload.new(file: uploaded, relative_path: "a/song.mp3").save!
    end
  end

  test "rejects a file that is not an MP3 by extension" do
    file = Rack::Test::UploadedFile.new(fixture_file("cover.jpg"), "image/jpeg")

    error = assert_raises(Upload::Error) { Upload.new(file: file).save! }

    assert_match(/Only MP3 files/, error.message)
  end

  test "rejects a file that is named .mp3 but is not one" do
    path = File.join(@temp_dir, "fake.mp3")
    File.binwrite(path, "definitely not audio")
    file = Rack::Test::UploadedFile.new(path, "audio/mpeg", original_filename: "fake.mp3")

    error = assert_raises(Upload::Error) { Upload.new(file: file).save! }

    assert_match(/Not a readable MP3/, error.message)
  end

  test "does not leave an unreadable file behind" do
    path = File.join(@temp_dir, "fake.mp3")
    File.binwrite(path, "definitely not audio")
    file = Rack::Test::UploadedFile.new(path, "audio/mpeg", original_filename: "fake.mp3")

    assert_raises(Upload::Error) { Upload.new(file: file).save! }

    assert_empty Dir.glob(new_dir("**/*.mp3"))
  end

  test "rejects a missing file" do
    error = assert_raises(Upload::Error) { Upload.new(file: nil).save! }

    assert_match(/No file/, error.message)
  end

  # The reason the relative path is treated as hostile.
  test "a traversing path cannot escape _NEW" do
    song = Upload.new(file: uploaded, relative_path: "../../../etc/evil.mp3").save!

    assert_equal new_dir("etc/evil.mp3"), song.file_path
    assert song.file_path.start_with?(new_dir), "the upload escaped _NEW"
  end

  test "an absolute path is confined to _NEW" do
    song = Upload.new(file: uploaded, relative_path: "/etc/passwd/evil.mp3").save!

    assert_equal new_dir("etc/passwd/evil.mp3"), song.file_path
  end

  test "backslash separators cannot escape either" do
    song = Upload.new(file: uploaded, relative_path: '..\\..\\evil.mp3').save!

    assert_equal new_dir("evil.mp3"), song.file_path
  end

  # Slashes here are the dragged folder structure, so they stay directories --
  # unlike a PathTemplate token value, where a slash is stripped.
  test "strips characters the filesystem rejects from each segment" do
    song = Upload.new(file: uploaded, relative_path: 'AC-DC/Live? "1978"/track*.mp3').save!

    assert_equal new_dir("AC-DC/Live 1978/track.mp3"), song.file_path
  end

  test "treats slashes in the relative path as folders" do
    song = Upload.new(file: uploaded, relative_path: "AC/DC/track.mp3").save!

    assert_equal new_dir("AC/DC/track.mp3"), song.file_path
  end

  test "rejects a path with nothing usable left" do
    error = assert_raises(Upload::Error) { Upload.new(file: uploaded, relative_path: "../..").save! }

    assert_match(/not usable|Only MP3/, error.message)
  end

  test "creates the destination directory tree" do
    Upload.new(file: uploaded, relative_path: "Deep/Nested/Path/song.mp3").save!

    assert Dir.exist?(new_dir("Deep/Nested/Path"))
  end

  test "the uploaded song is found by a later sync" do
    Upload.new(file: uploaded, relative_path: "Artist/song.mp3").save!

    assert_no_difference -> { Song.count } do
      LibrarySync.new(@temp_dir).call
    end
  end
end
