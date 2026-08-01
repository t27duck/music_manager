require "test_helper"

class LibrarySyncJobTest < ActiveJob::TestCase
  include LibraryTestHelper
  include ActionCable::TestHelper

  test "imports the library" do
    copy_fixture("song.mp3")

    assert_difference -> { Song.count }, 1 do
      LibrarySyncJob.perform_now
    end

    assert_predicate LibrarySync.status, :completed?
  end

  test "runs on the default queue" do
    assert_equal "default", LibrarySyncJob.new.queue_name
  end

  test "broadcasts progress while it runs" do
    copy_fixture("song.mp3")

    assert_broadcasts LibrarySync::STREAM, 3 do
      LibrarySyncJob.perform_now
    end
  end
end
