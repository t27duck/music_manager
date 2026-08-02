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

  test "does not re-read a file whose timestamp and size are unchanged" do
    copy_fixture("song.mp3")
    LibrarySync.new(@temp_dir).call

    # Neither pruning nor the seen-stamp touches Mp3File, so any call here is a
    # file being re-read.
    Mp3File.stub(:new, ->(*) { flunk "re-read a file that had not changed" }) do
      LibrarySync.new(@temp_dir).call
    end

    assert_equal 1, LibrarySync.status.skipped
  end

  # Skipped is not the same as unseen. Without the batched last_seen_at stamp,
  # #prune deletes the entire library on the second sync.
  test "a skipped file is not pruned" do
    copy_fixture("a.mp3")
    copy_fixture("b.mp3")
    LibrarySync.new(@temp_dir).call

    LibrarySync.new(@temp_dir).call

    assert_equal 2, songs_in_temp_dir.count
    assert_equal 2, LibrarySync.status.skipped
  end

  test "re-reads a file whose size changed even though its timestamp did not" do
    path = copy_fixture("song.mp3")
    LibrarySync.new(@temp_dir).call
    before = File.stat(path).mtime

    Mp3File.new(path).write_attributes(title: "Retagged In Place")
    File.utime(before, before, path)

    LibrarySync.new(@temp_dir).call

    assert_equal "Retagged In Place", Song.find_by(file_path: path).title
    assert_equal 0, LibrarySync.status.skipped
  end

  test "force re-reads every file no matter how unchanged it looks" do
    path = copy_fixture("song.mp3")
    LibrarySync.new(@temp_dir).call
    song = Song.find_by(file_path: path)
    on_disk = song.title

    # update_column bypasses the tag write-through, so the file still holds the
    # real title and only the database is wrong. A normal sync would skip the
    # file and never notice; this is exactly what the escape hatch is for.
    song.update_column(:title, "Wrong")

    LibrarySync.new(@temp_dir, force: true).call

    assert_equal on_disk, song.reload.title
    assert_equal 0, LibrarySync.status.skipped
  end

  test "without force, a file whose tags were only changed in the database is left alone" do
    path = copy_fixture("song.mp3")
    LibrarySync.new(@temp_dir).call
    song = Song.find_by(file_path: path)
    song.update_column(:title, "Wrong")

    LibrarySync.new(@temp_dir).call

    assert_equal "Wrong", song.reload.title
    assert_equal 1, LibrarySync.status.skipped
  end

  test "enqueue passes force through to the job" do
    assert_enqueued_with(job: LibrarySyncJob, args: [ { force: true } ]) do
      LibrarySync.enqueue(force: true)
    end
  end

  test "enqueue defaults to a timestamp-aware sync" do
    assert_enqueued_with(job: LibrarySyncJob, args: [ { force: false } ]) do
      LibrarySync.enqueue
    end
  end

  test "a song imported before timestamps were recorded is re-read once" do
    path = copy_fixture("song.mp3")
    LibrarySync.new(@temp_dir).call
    Song.find_by(file_path: path).update_column(:file_modified_at, nil)

    LibrarySync.new(@temp_dir).call

    assert_equal 0, LibrarySync.status.skipped
    assert_predicate Song.find_by(file_path: path).file_modified_at, :present?
  end

  # The skip can only tell that a file has not changed, not that what we extract
  # from it has. Without the epoch, adding a tag would leave it unread on every
  # existing song until someone happened to press Full rescan.
  test "the first sync of a new tag epoch re-reads even unchanged files" do
    path = copy_fixture("song.mp3")
    LibrarySync.new(@temp_dir).call
    assert_equal 0, LibrarySync.status.skipped

    Setting[LibrarySync::TAG_EPOCH_KEY] = LibrarySync::TAG_EPOCH - 1
    Mp3Info.open(path) { |mp3| mp3.tag2["TPE2"] = "Various Artists" }
    File.utime(File.stat(path).mtime, File.stat(path).mtime, path)

    LibrarySync.new(@temp_dir).call

    assert_equal 0, LibrarySync.status.skipped, "the epoch did not force a re-read"
    assert_equal "Various Artists", Song.find_by(file_path: path).album_artist
  end

  test "a completed sync records the tag epoch so the next one skips again" do
    copy_fixture("song.mp3")

    LibrarySync.new(@temp_dir).call
    assert_equal LibrarySync::TAG_EPOCH, Setting[LibrarySync::TAG_EPOCH_KEY].to_i

    LibrarySync.new(@temp_dir).call

    assert_equal 1, LibrarySync.status.skipped
  end

  test "a failed sync leaves the epoch behind so the re-read is retried" do
    copy_fixture("song.mp3")
    Setting[LibrarySync::TAG_EPOCH_KEY] = LibrarySync::TAG_EPOCH - 1

    SongImporter.stub(:call, ->(_) { raise "disk on fire" }) do
      assert_raises(RuntimeError) { LibrarySync.new(@temp_dir).call }
    end

    assert_operator Setting[LibrarySync::TAG_EPOCH_KEY].to_i, :<, LibrarySync::TAG_EPOCH
  end

  test "records one run per sync" do
    copy_fixture("a.mp3")
    copy_fixture("b.mp3")

    assert_difference -> { SyncRun.count }, 1 do
      LibrarySync.new(@temp_dir).call
    end

    run = SyncRun.recent.first
    assert_predicate run, :completed?
    assert_equal 2, run.total
    assert_predicate run.finished_at, :present?
  end

  test "records a forced sync as a full rescan" do
    copy_fixture("a.mp3")

    LibrarySync.new(@temp_dir, force: true).call

    assert_predicate SyncRun.recent.first, :forced?
  end

  test "records how many files were skipped" do
    copy_fixture("a.mp3")
    LibrarySync.new(@temp_dir).call

    LibrarySync.new(@temp_dir).call

    assert_equal 1, SyncRun.recent.first.skipped
  end

  test "records the per-file errors of a tolerated failure" do
    File.binwrite(File.join(@temp_dir, "broken.mp3"), "not audio")

    LibrarySync.new(@temp_dir).call

    assert_match(/broken\.mp3/, SyncRun.recent.first.failures.first)
  end

  test "records a run that blew up as failed" do
    copy_fixture("a.mp3")

    SongImporter.stub(:call, ->(_) { raise "disk on fire" }) do
      assert_raises(RuntimeError) { LibrarySync.new(@temp_dir).call }
    end

    assert_predicate SyncRun.recent.first, :failed?
  end

  # The row is written from #call, not from publish -- which is what makes it
  # survive a test that stubs publish wholesale.
  test "the run is recorded even when publishing is stubbed out" do
    copy_fixture("a.mp3")

    assert_difference -> { SyncRun.count }, 1 do
      LibrarySync.stub(:publish, ->(status) { status }) do
        LibrarySync.new(@temp_dir).call
      end
    end
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
