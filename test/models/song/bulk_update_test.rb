require "test_helper"

class Song::BulkUpdateTest < ActiveSupport::TestCase
  include LibraryTestHelper

  GIF = "GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xFF\xFF\xFF!\xF9\x04\x00\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;".b

  setup do
    @one = create_test_song("a.mp3", title: "One", artist: "Old Artist", genre: "Rock")
    @two = create_test_song("b.mp3", title: "Two", artist: "Old Artist", genre: "Rock")
  end

  test "applies the given fields to every song" do
    result = Song::BulkUpdate.new([ @one, @two ], attributes: { "artist" => "New Artist" }).call

    assert_equal 2, result.updated_count
    assert_not_predicate result, :any_failures?
    assert_equal [ "New Artist", "New Artist" ], [ @one.reload.artist, @two.reload.artist ]
  end

  test "writes the change to every file" do
    Song::BulkUpdate.new([ @one, @two ], attributes: { "album" => "Shared Album" }).call

    assert_equal "Shared Album", tags_on_disk(@one.file_path)[:album]
    assert_equal "Shared Album", tags_on_disk(@two.file_path)[:album]
  end

  test "leaves blank fields alone rather than clearing them" do
    Song::BulkUpdate.new([ @one ], attributes: { "artist" => "Changed", "genre" => "" }).call

    assert_equal "Changed", @one.reload.artist
    assert_equal "Rock", @one.genre
  end

  test "ignores fields that are not offered in bulk" do
    Song::BulkUpdate.new([ @one ], attributes: { "title" => "Renamed", "artist" => "Fine" }).call

    assert_equal "One", @one.reload.title
    assert_equal "Fine", @one.artist
  end

  test "assigns album art to every song" do
    result = Song::BulkUpdate.new([ @one, @two ], album_art: GIF).call

    assert_equal 2, result.updated_count
    assert_equal GIF, @one.reload.album_art
    assert_equal GIF, @two.reload.album_art
  end

  test "removes album art from every song" do
    Song::BulkUpdate.new([ @one, @two ], album_art: GIF).call

    Song::BulkUpdate.new([ @one, @two ], remove_album_art: true).call

    assert_not_predicate @one.reload, :album_art?
    assert_not_predicate @two.reload, :album_art?
  end

  test "an uploaded image wins over the remove checkbox" do
    Song::BulkUpdate.new([ @one ], album_art: GIF, remove_album_art: true).call

    assert_equal GIF, @one.reload.album_art
  end

  test "applies fields and art together" do
    Song::BulkUpdate.new([ @one ], attributes: { "album" => "Both" }, album_art: GIF).call

    assert_equal "Both", @one.reload.album
    assert_equal GIF, @one.album_art
  end

  # The reason there is no wrapping transaction.
  test "one unwritable file does not undo the songs that succeeded" do
    File.binwrite(@two.file_path, "no longer valid audio")

    result = Song::BulkUpdate.new([ @one, @two ], attributes: { "artist" => "New Artist" }).call

    assert_equal 1, result.updated_count
    assert_equal 1, result.failure_count
    assert_equal "New Artist", @one.reload.artist, "the writable song was rolled back"
    assert_equal "Old Artist", @two.reload.artist
  end

  test "a failure carries the song and a useful message" do
    File.binwrite(@two.file_path, "no longer valid audio")

    result = Song::BulkUpdate.new([ @two ], attributes: { "artist" => "New" }).call

    failure = result.failures.sole
    assert_equal @two, failure.song
    assert_match(/Could not write tags/, failure.message)
  end

  test "an invalid image fails every song without changing them" do
    result = Song::BulkUpdate.new([ @one, @two ], album_art: "not an image").call

    assert_equal 2, result.failure_count
    assert_match(/JPEG, PNG or GIF/, result.failures.first.message)
    assert_not_predicate @one.reload, :album_art?
  end

  test "summarises what happened" do
    assert_equal "2 songs updated.",
      Song::BulkUpdate.new([ @one, @two ], attributes: { "artist" => "X" }).call.summary
  end

  test "the summary names the failures" do
    File.binwrite(@two.file_path, "no longer valid audio")

    summary = Song::BulkUpdate.new([ @one, @two ], attributes: { "artist" => "X" }).call.summary

    assert_equal "1 song updated, 1 failed.", summary
  end

  test "changes? reports whether there is anything to do" do
    assert_not_predicate Song::BulkUpdate.new([ @one ]), :changes?
    assert_not_predicate Song::BulkUpdate.new([ @one ], attributes: { "artist" => "  " }), :changes?
    assert_predicate Song::BulkUpdate.new([ @one ], attributes: { "artist" => "X" }), :changes?
    assert_predicate Song::BulkUpdate.new([ @one ], album_art: GIF), :changes?
    assert_predicate Song::BulkUpdate.new([ @one ], remove_album_art: true), :changes?
  end

  test "an empty selection does nothing" do
    result = Song::BulkUpdate.new([], attributes: { "artist" => "X" }).call

    assert_predicate result, :nothing_to_do?
  end
end
