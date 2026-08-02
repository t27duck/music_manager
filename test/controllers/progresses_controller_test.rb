require "test_helper"

class ProgressesControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper

  test "reports the current status" do
    LibrarySync.publish(LibrarySync::Status.starting)

    get progress_url, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target=progress]"
  end

  test "works when nothing has ever run" do
    get progress_url, as: :turbo_stream

    assert_response :success
  end

  # The endpoint reports whatever is current, not one named operation -- that is
  # why it is its own resource rather than syncs#show.
  test "reports progress whichever operation published it" do
    LibrarySync.publish(
      LibrarySync::Status.new(state: :running, current: 4, total: 8,
        filename: "track.mp3", errors: [], finished_at: nil, skipped: 0)
    )

    get progress_url, as: :turbo_stream

    assert_select "turbo-stream[target=progress]"
    assert_select "turbo-stream[target=sync_button]"
  end
end
