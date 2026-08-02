require "test_helper"

class SyncsControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper
  include ActiveJob::TestHelper

  test "create enqueues a sync" do
    assert_enqueued_with(job: LibrarySyncJob) do
      post sync_url, as: :turbo_stream
    end

    assert_response :success
  end

  test "create marks the sync as running so the button disables immediately" do
    post sync_url, as: :turbo_stream

    assert_predicate LibrarySync, :running?
    assert_select "turbo-stream[target=sync_button]"
    assert_select "turbo-stream[target=progress]"
  end

  test "create enqueues a forced sync when the rescan button is used" do
    assert_enqueued_with(job: LibrarySyncJob, args: [ { force: true } ]) do
      post sync_url, params: { force: "1" }, as: :turbo_stream
    end
  end

  test "create enqueues an ordinary sync by default" do
    assert_enqueued_with(job: LibrarySyncJob, args: [ { force: false } ]) do
      post sync_url, as: :turbo_stream
    end
  end

  test "create treats a falsey force param as an ordinary sync" do
    assert_enqueued_with(job: LibrarySyncJob, args: [ { force: false } ]) do
      post sync_url, params: { force: "0" }, as: :turbo_stream
    end
  end

  test "create does not start a second sync while one is running" do
    LibrarySync.enqueue

    assert_no_enqueued_jobs(only: LibrarySyncJob) do
      post sync_url, as: :turbo_stream
    end
  end

  test "create redirects for a plain HTML request" do
    post sync_url

    assert_redirected_to root_path
  end

  test "the sync button renders in the layout" do
    get root_url

    assert_select "#sync_button button", text: /Sync library/
  end

  test "the full rescan button renders alongside it" do
    get root_url

    assert_select "#sync_button button", text: /Full rescan/
    assert_select "#sync_button input[name=force][value='1']"
  end

  test "the sync button is disabled while a sync is running" do
    LibrarySync.enqueue

    get root_url

    assert_select "#sync_button button[disabled]"
    assert_select "#sync_button button", text: /Syncing/
  end

  test "the progress bar renders while a sync is running" do
    LibrarySync.publish(
      LibrarySync::Status.new(state: :running, current: 3, total: 10,
        filename: "track.mp3", errors: [], finished_at: nil, skipped: 0)
    )

    get root_url

    assert_select "#progress [role=progressbar][aria-valuenow=30]"
    assert_select "#progress", text: /3\/10/
    assert_select "#progress", text: /track\.mp3/
  end

  test "the progress bar is absent when no sync has run" do
    get root_url

    assert_select "#progress", text: ""
  end

  test "a completed sync auto-hides" do
    LibrarySync.publish(
      LibrarySync::Status.new(state: :completed, current: 5, total: 5,
        filename: nil, errors: [], finished_at: Time.current, skipped: 0)
    )

    get root_url

    assert_select "#progress [data-controller=auto-hide]"
    assert_select "#progress", text: /Sync complete/
  end

  test "a failed sync is reported in red" do
    LibrarySync.publish(
      LibrarySync::Status.new(state: :failed, current: 0, total: 0,
        filename: nil, errors: [ "boom" ], finished_at: Time.current, skipped: 0)
    )

    get root_url

    assert_select "#progress .text-red-400", text: /Sync failed/
  end

  test "the page subscribes to the sync stream" do
    get root_url

    assert_select "turbo-cable-stream-source[channel='Turbo::StreamsChannel']"
  end
end
