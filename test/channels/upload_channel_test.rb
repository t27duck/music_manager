require "test_helper"

class UploadChannelTest < ActionCable::Channel::TestCase
  test "subscribes to the stream for its upload id" do
    subscribe upload_id: "abc-123"

    assert_predicate subscription, :confirmed?
    assert_has_stream "uploads:abc-123"
  end

  test "rejects a subscription with no upload id" do
    subscribe

    assert_predicate subscription, :rejected?
  end

  test "does not subscribe to another session's stream" do
    subscribe upload_id: "abc-123"

    assert_has_no_stream "uploads:other-session"
  end

  test "broadcast_result sends the outcome of one file" do
    assert_broadcast_on("uploads:abc-123", status: "ok", filename: "song.mp3", message: "Imported") do
      UploadChannel.broadcast_result(
        upload_id: "abc-123", status: "ok", filename: "song.mp3", message: "Imported"
      )
    end
  end

  test "broadcast_result does nothing without an upload id" do
    assert_no_broadcasts("uploads:") do
      UploadChannel.broadcast_result(
        upload_id: nil, status: "ok", filename: "song.mp3", message: "Imported"
      )
    end
  end
end
