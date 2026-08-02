require "test_helper"

class FileOrganizationJobTest < ActiveJob::TestCase
  include LibraryTestHelper

  test "moves the songs it was given" do
    song = create_test_song("loose/one.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album: "Afterglow", track_number: 7)

    FileOrganizationJob.perform_now(song_ids: [ song.id ], template: PathTemplate::DEFAULT)

    assert_equal File.join(@temp_dir, "Neon Fields/Afterglow/07 - Midnight Drive.mp3"),
      song.reload.file_path
  end

  test "runs on the default queue" do
    assert_equal "default", FileOrganizationJob.new.queue_name
  end

  # Ids and a string, never records: the selection can be the whole library and
  # this has to survive a JSON round trip through the queue in production.
  test "its arguments serialize" do
    arguments = [ { song_ids: [ 1, 2, 3 ], template: "<Artist>/<Title>" } ]

    assert_equal arguments,
      ActiveJob::Arguments.deserialize(ActiveJob::Arguments.serialize(arguments))
  end
end
