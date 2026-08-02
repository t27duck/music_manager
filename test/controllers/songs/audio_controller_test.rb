require "test_helper"

class Songs::AudioControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper

  setup do
    @song = create_test_song("a.mp3", title: "Midnight Drive")
    @size = File.size(@song.file_path)
  end

  test "serves the whole file as audio" do
    get song_audio_url(@song)

    assert_response :success
    assert_equal "audio/mpeg", response.media_type
    assert_equal File.binread(@song.file_path), response.body.b
  end

  # Without this some browsers do not offer a scrub bar at all, even though the
  # server would answer a range request.
  test "advertises that it accepts byte ranges" do
    get song_audio_url(@song)

    assert_equal "bytes", response.headers["Accept-Ranges"]
  end

  # The reason this endpoint exists rather than a send_file one: send_file and
  # send_data ignore Range entirely and answer 200 with the whole body, so
  # seeking in a six-megabyte file would silently not work.
  test "a range request is answered with exactly those bytes" do
    get song_audio_url(@song), headers: { "Range" => "bytes=100-199" }

    assert_response :partial_content
    assert_equal "bytes 100-199/#{@size}", response.headers["Content-Range"]
    assert_equal 100, response.body.bytesize
    assert_equal File.binread(@song.file_path, 100, 100), response.body.b
  end

  test "an open-ended range runs to the end of the file" do
    get song_audio_url(@song), headers: { "Range" => "bytes=#{@size - 50}-" }

    assert_response :partial_content
    assert_equal "bytes #{@size - 50}-#{@size - 1}/#{@size}", response.headers["Content-Range"]
    assert_equal 50, response.body.bytesize
  end

  test "a range past the end of the file is refused" do
    get song_audio_url(@song), headers: { "Range" => "bytes=#{@size + 1000}-" }

    assert_response :range_not_satisfiable
    assert_equal "bytes */#{@size}", response.headers["Content-Range"]
  end

  test "an unchanged file is answered with not modified" do
    get song_audio_url(@song),
      headers: { "If-Modified-Since" => File.mtime(@song.file_path).httpdate }

    assert_response :not_modified
  end

  test "404s when the file is gone from disk" do
    File.delete(@song.file_path)

    get song_audio_url(@song)

    assert_response :not_found
  end

  test "404s for an unknown song" do
    get song_audio_url(song_id: 0)

    assert_response :not_found
  end

  # The URL is keyed on the song id, so a file organize -- which changes
  # file_path and keeps the row -- does not break a link or an open player.
  test "keeps working after the file moves" do
    url = song_audio_url(@song)
    moved = File.join(@temp_dir, "moved.mp3")
    FileUtils.mv(@song.file_path, moved)
    @song.update_column(:file_path, moved)

    get url

    assert_response :success
  end
end
