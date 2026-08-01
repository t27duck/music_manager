require "test_helper"

class UploadsControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper
  include ActionCable::TestHelper

  def mp3(name = "song.mp3")
    fixture_file_upload(LibraryTestHelper::FIXTURE_MP3, "audio/mpeg").tap do |file|
      file.define_singleton_method(:original_filename) { name }
    end
  end

  def new_dir(*parts) = File.join(@temp_dir, Upload::DESTINATION, *parts)

  test "show renders the dropzone" do
    get upload_url

    assert_response :success
    assert_select "[data-controller=upload]"
    assert_select "input[type=file]", minimum: 1
  end

  test "the upload page is linked from the navigation" do
    get root_url

    assert_select "nav a[href=?]", upload_path, text: "Upload"
  end

  test "create saves the file and imports it" do
    assert_difference -> { Song.count }, 1 do
      post upload_url, params: { file: mp3 }
    end

    assert_response :created
    assert_equal new_dir("song.mp3"), Song.last.file_path
  end

  test "create preserves the dropped folder structure" do
    post upload_url, params: { file: mp3, relative_path: "Artist/Album/track.mp3" }

    assert_equal new_dir("Artist/Album/track.mp3"), Song.last.file_path
  end

  test "create answers with the imported song" do
    post upload_url, params: { file: mp3 }

    body = response.parsed_body
    assert_equal "ok", body["status"]
    assert_equal "Test Song One", body["title"]
  end

  test "create rejects a file that is not an MP3" do
    file = fixture_file_upload("cover.jpg", "image/jpeg")

    assert_no_difference -> { Song.count } do
      post upload_url, params: { file: file }
    end

    assert_response :unprocessable_entity
    assert_equal "error", response.parsed_body["status"]
    assert_match(/Only MP3 files/, response.parsed_body["message"])
  end

  test "create rejects a request with no file" do
    post upload_url

    assert_response :unprocessable_entity
    assert_match(/No file/, response.parsed_body["message"])
  end

  test "create confines a traversing path to _NEW" do
    post upload_url, params: { file: mp3, relative_path: "../../../etc/evil.mp3" }

    assert_response :created
    assert_equal new_dir("etc/evil.mp3"), Song.last.file_path
  end

  test "re-uploading the same path updates rather than duplicating" do
    post upload_url, params: { file: mp3, relative_path: "a/song.mp3" }

    assert_no_difference -> { Song.count } do
      post upload_url, params: { file: mp3, relative_path: "a/song.mp3" }
    end
  end

  test "create broadcasts the result to the upload's own stream" do
    assert_broadcasts UploadChannel.stream_name_for("abc-123"), 1 do
      post upload_url, params: { file: mp3, upload_id: "abc-123" }
    end
  end

  test "create broadcasts failures too" do
    file = fixture_file_upload("cover.jpg", "image/jpeg")

    assert_broadcasts UploadChannel.stream_name_for("abc-123"), 1 do
      post upload_url, params: { file: file, upload_id: "abc-123" }
    end
  end

  test "create does not broadcast without an upload id" do
    assert_no_broadcasts UploadChannel.stream_name_for("") do
      post upload_url, params: { file: mp3 }
    end
  end

  test "one upload's stream does not receive another's messages" do
    assert_no_broadcasts UploadChannel.stream_name_for("other-session") do
      post upload_url, params: { file: mp3, upload_id: "abc-123" }
    end
  end
end
