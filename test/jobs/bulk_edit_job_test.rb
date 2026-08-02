require "test_helper"

class BulkEditJobTest < ActiveJob::TestCase
  include LibraryTestHelper

  test "applies the changes to the songs it was given" do
    song = create_test_song("a.mp3", title: "One", artist: "Old Artist")

    BulkEditJob.perform_now(song_ids: [ song.id ], attributes: { "artist" => "New Artist" })

    assert_equal "New Artist", song.reload.artist
  end

  test "runs on the default queue" do
    assert_equal "default", BulkEditJob.new.queue_name
  end

  # Ids and primitives only: the selection can be the whole library, and the
  # album art travels as a path because the bytes cannot ride in arguments.
  test "its arguments serialize" do
    arguments = [ {
      song_ids: [ 1, 2, 3 ],
      attributes: { "artist" => "X" },
      album_art_path: "/tmp/spooled.bin",
      remove_album_art: false
    } ]

    assert_equal arguments,
      ActiveJob::Arguments.deserialize(ActiveJob::Arguments.serialize(arguments))
  end
end
