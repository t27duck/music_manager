require "application_system_test_case"

class UploadTest < ApplicationSystemTestCase
  include LibraryTestHelper

  # Selenium cannot synthesise a directory drag-and-drop, so these drive the
  # click-to-browse fallback. It shares the whole upload path with the dropzone;
  # only the way the file list is gathered differs.
  def attach_mp3(*paths)
    attach_file("MP3 files to upload", paths, make_visible: true)
  end

  def scratch_mp3(name)
    File.join(@temp_dir, name).tap do |path|
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(fixture_file(LibraryTestHelper::FIXTURE_MP3), path)
    end
  end

  def new_dir(*parts) = File.join(@temp_dir, Upload::DESTINATION, *parts)

  test "uploading a file imports it and reports progress" do
    visit upload_path
    assert_text "Drop MP3 files or folders here"

    attach_mp3 scratch_mp3("uploads/one.mp3")

    assert_text "1 of 1 uploaded."
    assert_text "Imported Test Song One"
    assert_selector "[role=progressbar]"
    assert_text "Upload complete"
    assert_no_text "Uploading…"

    assert_equal new_dir("one.mp3"), Song.last.file_path
    assert File.exist?(new_dir("one.mp3"))
  end

  test "uploading several files counts them" do
    visit upload_path

    attach_mp3 scratch_mp3("uploads/one.mp3"), scratch_mp3("uploads/two.mp3"),
      scratch_mp3("uploads/three.mp3")

    assert_text "3 of 3 uploaded."
    assert_equal 3, Song.in_library(@temp_dir).count
  end

  test "the log names each file the server handled" do
    visit upload_path

    attach_mp3 scratch_mp3("uploads/first.mp3"), scratch_mp3("uploads/second.mp3")

    assert_text "2 of 2 uploaded."
    assert_selector "[data-upload-target=log]", text: /first\.mp3/
    assert_selector "[data-upload-target=log]", text: /second\.mp3/
  end

  test "a non-MP3 file is rejected and reported" do
    visit upload_path

    attach_mp3 fixture_file("cover.jpg")

    assert_text "0 of 1 uploaded, 1 failed."
    assert_text "Only MP3 files can be uploaded"
    assert_equal 0, Song.in_library(@temp_dir).count
  end

  test "a bad file does not stop the good ones" do
    visit upload_path

    attach_mp3 fixture_file("cover.jpg"), scratch_mp3("uploads/good.mp3")

    assert_text "1 of 2 uploaded, 1 failed."
    assert_equal 1, Song.in_library(@temp_dir).count
    assert File.exist?(new_dir("good.mp3"))
  end

  test "uploaded songs appear in the library" do
    visit upload_path
    attach_mp3 scratch_mp3("uploads/one.mp3")
    assert_text "1 of 1 uploaded."

    click_on "Songs"

    assert_text "Test Song One"
    assert_text "1 song"
  end

  test "re-uploading the same file does not duplicate it" do
    visit upload_path
    attach_mp3 scratch_mp3("uploads/one.mp3")
    assert_text "1 of 1 uploaded."

    attach_mp3 scratch_mp3("uploads/one.mp3")
    assert_text "1 of 1 uploaded."

    assert_equal 1, Song.in_library(@temp_dir).count
  end

  test "the upload page is reachable from the navigation" do
    visit root_path

    click_on "Upload"

    assert_selector "h1", text: "Upload"
    assert_selector "nav a[aria-current=page]", text: "Upload"
  end
end
