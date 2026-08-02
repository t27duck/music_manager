require "test_helper"

class BulkEditTest < ActiveSupport::TestCase
  include LibraryTestHelper
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    @one = create_test_song("a.mp3", title: "One", artist: "Old Artist")
    @two = create_test_song("b.mp3", title: "Two", artist: "Old Artist")
  end

  def edit(songs = [ @one, @two ], **options)
    BulkEdit.call(song_ids: songs.map(&:id), **options)
  end

  test "applies the changes to every song it was given" do
    edit(attributes: { "artist" => "New Artist" })

    assert_equal "New Artist", @one.reload.artist
    assert_equal "New Artist", @two.reload.artist
  end

  test "writes the changes through to the files" do
    edit(attributes: { "genre" => "Ambient" })

    assert_equal "Ambient", tags_on_disk(@one.file_path)[:genre]
  end

  test "publishes a completed status carrying the summary" do
    edit(attributes: { "artist" => "New Artist" })

    status = BulkEdit.status
    assert_predicate status, :completed?
    assert_equal 2, status.updated
    assert_equal 2, status.total
    assert_equal 100, status.percent
    assert_equal "2 songs updated.", status.summary
  end

  test "records a failure without losing the successes" do
    File.binwrite(@two.file_path, "no longer valid audio")

    edit(attributes: { "artist" => "New Artist" })

    assert_equal "New Artist", @one.reload.artist
    assert_equal 1, BulkEdit.status.updated
    assert_predicate BulkEdit.status, :errors?
    assert_match(/Could not write tags/, BulkEdit.status.errors.first)
  end

  test "the status survives a round trip through the cache" do
    edit(attributes: { "artist" => "New Artist" })

    status = BulkEdit.status
    assert_equal status, Marshal.load(Marshal.dump(status))
  end

  test "the status holds no Active Record objects" do
    edit(attributes: { "artist" => "New Artist" })

    BulkEdit.status.deconstruct_keys(nil).each_value do |value|
      Array(value).each { |element| assert_not_kind_of ActiveRecord::Base, element }
    end
  end

  # Album art cannot ride in job arguments, so it is spooled to disk at enqueue
  # time and the path travels instead.
  test "applies album art spooled to disk" do
    path = BulkEdit.spool_album_art(File.binread(fixture_file("cover.jpg")))

    edit(album_art_path: path)

    assert_predicate @one.reload, :album_art?
    assert_predicate @two.reload, :album_art?
  end

  test "deletes the spooled album art when the run finishes" do
    path = BulkEdit.spool_album_art(File.binread(fixture_file("cover.jpg")))

    edit(album_art_path: path)

    assert_not File.exist?(path), "the spooled album art was left on disk"
  end

  test "deletes the spooled album art even when the run blows up" do
    path = BulkEdit.spool_album_art(File.binread(fixture_file("cover.jpg")))

    Song::BulkUpdate.stub(:new, ->(*, **) { raise "disk on fire" }) do
      assert_raises(RuntimeError) { edit(album_art_path: path) }
    end

    assert_not File.exist?(path), "the spooled album art outlived a failed run"
  end

  test "spool_album_art ignores blank data" do
    assert_nil BulkEdit.spool_album_art(nil)
    assert_nil BulkEdit.spool_album_art("")
  end

  test "can remove album art across the selection" do
    cover = File.binread(fixture_file("cover.jpg"))
    [ @one, @two ].each { |song| song.update_album_art!(cover) }

    edit(remove_album_art: true)

    assert_not_predicate @one.reload, :album_art?
    assert_not_predicate @two.reload, :album_art?
  end

  test "broadcasts progress to the shared stream" do
    assert_broadcasts ProgressReporting::STREAM, 3 do
      edit([ @one ], attributes: { "artist" => "New Artist" })
    end
  end

  test "enqueue refuses while another operation is running" do
    LibrarySync.publish(LibrarySync::Status.starting)

    assert_no_enqueued_jobs(only: BulkEditJob) do
      assert_not BulkEdit.enqueue(song_ids: [ @one.id ], attributes: { "artist" => "X" })
    end
  end

  test "a bulk edit in flight blocks a sync" do
    BulkEdit.enqueue(song_ids: [ @one.id ], attributes: { "artist" => "X" })

    assert_not LibrarySync.enqueue
  end

  test "reports a failed status and re-raises when something unexpected blows up" do
    Song::BulkUpdate.stub(:new, ->(*, **) { raise "disk on fire" }) do
      assert_raises(RuntimeError) { edit(attributes: { "artist" => "X" }) }
    end

    assert_predicate BulkEdit.status, :failed?
    assert_not_predicate ProgressReporting, :busy?
  end
end
