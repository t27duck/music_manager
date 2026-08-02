require "test_helper"

class FileOrganizationTest < ActiveSupport::TestCase
  include LibraryTestHelper
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    @song = create_test_song("loose/one.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album: "Afterglow", track_number: 7)
  end

  def organize(songs = [ @song ], template: PathTemplate::DEFAULT)
    FileOrganization.call(song_ids: songs.map(&:id), template: template)
  end

  test "moves the songs it was given" do
    organize

    expected = File.join(@temp_dir, "Neon Fields/Afterglow/07 - Midnight Drive.mp3")
    assert_equal expected, @song.reload.file_path
    assert File.exist?(expected)
  end

  test "publishes a completed status carrying the summary" do
    organize

    status = FileOrganization.status
    assert_predicate status, :completed?
    assert_equal 1, status.moved
    assert_equal 1, status.total
    assert_equal 100, status.percent
    assert_equal "1 file moved.", status.summary
    assert_predicate status.finished_at, :present?
  end

  test "counts files that were already in place" do
    organize
    organize

    assert_equal 0, FileOrganization.status.moved
    assert_equal 1, FileOrganization.status.unchanged
  end

  # The reason the status is built out of primitives rather than reusing
  # FileOrganizer::Result: Result holds Move objects, which hold live Song
  # records, and the cache Marshals whatever it is given.
  test "the status survives a round trip through the cache" do
    organize

    status = FileOrganization.status
    round_tripped = Marshal.load(Marshal.dump(status))

    assert_equal status, round_tripped
  end

  test "the status holds no Active Record objects" do
    organize

    FileOrganization.status.deconstruct_keys(nil).each_value do |value|
      Array(value).each do |element|
        assert_not_kind_of ActiveRecord::Base, element
        assert_not_kind_of FileOrganizer::Move, element
      end
    end
  end

  test "records a failure without aborting the rest" do
    other = create_test_song("loose/two.mp3", title: "Second", artist: "Neon Fields",
      album: "Afterglow", track_number: 7)

    # Both render to the same destination; the second is suffixed, not lost.
    organize([ @song, other ])

    assert_equal 2, FileOrganization.status.moved
    assert_not_equal @song.reload.file_path, other.reload.file_path
  end

  test "remembers the template only once the moves have happened" do
    organize(template: "<Genre>/<Title>")

    assert_equal "<Genre>/<Title>", Setting[:path_template]
  end

  test "broadcasts progress to the shared stream" do
    assert_broadcasts ProgressReporting::STREAM, 3 do
      organize
    end
  end

  test "enqueue refuses while another operation is running" do
    LibrarySync.publish(LibrarySync::Status.starting)

    assert_no_enqueued_jobs(only: FileOrganizationJob) do
      assert_not FileOrganization.enqueue(song_ids: [ @song.id ], template: PathTemplate::DEFAULT)
    end
  end

  test "enqueue marks the work as started so the buttons disable immediately" do
    assert_enqueued_with(job: FileOrganizationJob) do
      assert FileOrganization.enqueue(song_ids: [ @song.id ], template: PathTemplate::DEFAULT)
    end

    assert_predicate ProgressReporting, :busy?
  end

  # Operations share one region, so a sync must not start on top of an organize.
  test "an organize in flight blocks a sync" do
    FileOrganization.enqueue(song_ids: [ @song.id ], template: PathTemplate::DEFAULT)

    assert_not LibrarySync.enqueue
  end

  test "reports a failed status and re-raises when something unexpected blows up" do
    FileOrganizer.stub(:new, ->(*) { raise "disk on fire" }) do
      assert_raises(RuntimeError) { organize }
    end

    assert_predicate FileOrganization.status, :failed?
    assert_not_predicate ProgressReporting, :busy?
  end
end
