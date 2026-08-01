require "test_helper"

class LibrarySyncTest < ActiveSupport::TestCase
  include LibraryTestHelper
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  test "imports every MP3 under the library root" do
    copy_fixture("top.mp3")
    copy_fixture("Artist/Album/nested.mp3")

    assert_difference -> { Song.count }, 2 do
      LibrarySync.new(@temp_dir).call
    end
  end

  test "updates a song whose tags changed on disk rather than skipping it" do
    path = copy_fixture("song.mp3")
    LibrarySync.new(@temp_dir).call
    Mp3File.new(path).write_attributes(title: "Retagged Externally")

    assert_no_difference -> { Song.count } do
      LibrarySync.new(@temp_dir).call
    end

    assert_equal "Retagged Externally", Song.find_by(file_path: path).title
  end

  test "removes songs whose files were deleted from disk" do
    kept = copy_fixture("kept.mp3")
    removed = copy_fixture("removed.mp3")
    LibrarySync.new(@temp_dir).call
    File.delete(removed)

    LibrarySync.new(@temp_dir).call

    assert_equal [ kept ], songs_in_temp_dir.pluck(:file_path)
  end

  test "does not remove songs that live outside the library root" do
    outside = create_test_song("song.mp3")
    other_root = Dir.mktmpdir("other_library")

    LibrarySync.new(other_root).call

    assert Song.exists?(outside.id), "a song outside the synced root was pruned"
  ensure
    FileUtils.remove_entry(other_root) if other_root && Dir.exist?(other_root)
  end

  test "one unreadable file does not abort the run" do
    copy_fixture("good_one.mp3")
    File.binwrite(File.join(@temp_dir, "broken.mp3"), "not audio")
    copy_fixture("good_two.mp3")

    LibrarySync.new(@temp_dir).call

    assert_equal 2, songs_in_temp_dir.count
    assert_predicate LibrarySync.status, :completed?
    assert_predicate LibrarySync.status, :errors?
  end

  test "keeps a song whose file became unreadable instead of pruning it" do
    path = copy_fixture("song.mp3")
    LibrarySync.new(@temp_dir).call
    File.binwrite(path, "no longer valid audio")

    LibrarySync.new(@temp_dir).call

    assert_equal 1, songs_in_temp_dir.count, "an unreadable but present file was pruned"
  end

  test "publishes a completed status with the final count" do
    copy_fixture("a.mp3")
    copy_fixture("b.mp3")

    LibrarySync.new(@temp_dir).call

    status = LibrarySync.status
    assert_predicate status, :completed?
    assert_equal 2, status.total
    assert_equal 2, status.current
    assert_equal 100, status.percent
    assert_predicate status.finished_at, :present?
  end

  test "completes cleanly on an empty library" do
    LibrarySync.new(@temp_dir).call

    assert_predicate LibrarySync.status, :completed?
    assert_equal 0, LibrarySync.status.total
  end

  test "broadcasts progress to the sync stream" do
    copy_fixture("a.mp3")

    assert_broadcasts LibrarySync::STREAM, 3 do
      LibrarySync.new(@temp_dir).call
    end
  end

  test "reports a failed status and re-raises when something unexpected blows up" do
    copy_fixture("song.mp3")

    SongImporter.stub(:call, ->(_path) { raise "disk on fire" }) do
      assert_raises(RuntimeError) { LibrarySync.new(@temp_dir).call }
    end

    assert_predicate LibrarySync.status, :failed?
    assert_not_predicate LibrarySync, :running?
  end

  test "running? reflects the published status" do
    assert_not_predicate LibrarySync, :running?

    LibrarySync.publish(LibrarySync::Status.starting)
    assert_predicate LibrarySync, :running?

    LibrarySync.new(@temp_dir).call
    assert_not_predicate LibrarySync, :running?
  end

  test "enqueue queues the job and marks the sync as running immediately" do
    assert_enqueued_with(job: LibrarySyncJob) do
      assert LibrarySync.enqueue
    end

    assert_predicate LibrarySync, :running?
  end

  test "enqueue refuses to start a second sync while one is running" do
    LibrarySync.enqueue

    assert_no_enqueued_jobs(only: LibrarySyncJob) do
      assert_not LibrarySync.enqueue
    end
  end

  test "the counter never moves backwards" do
    12.times { |i| copy_fixture("song#{i}.mp3") }
    seen = []

    LibrarySync.stub(:publish, ->(status) { seen << status.current; status }) do
      LibrarySync.new(@temp_dir).call
    end

    assert_equal seen.sort, seen, "progress counter moved backwards: #{seen.inspect}"
    assert_equal 12, seen.last
  end
end
