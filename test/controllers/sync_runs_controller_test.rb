require "test_helper"

class SyncRunsControllerTest < ActionDispatch::IntegrationTest
  def completed(**overrides)
    SyncRun.start!.tap do |run|
      run.finish!(
        LibrarySync::Status.new(
          **{ state: :completed, current: 4, total: 4, filename: nil, errors: [],
              finished_at: Time.current, skipped: 0 },
          **overrides
        )
      )
    end
  end

  test "index lists past runs" do
    completed(total: 12, skipped: 9)

    get sync_runs_url

    assert_response :success
    assert_select "h1", text: "Sync history"
    assert_select "tbody tr", count: 1
    assert_select "tbody tr", text: /12/
  end

  test "index orders newest first" do
    older = completed
    newer = completed

    get sync_runs_url

    ids = css_select("tbody tr").map { |row| row["id"] }
    assert_equal [ dom_id(newer), dom_id(older) ], ids
  end

  test "index paginates" do
    (SyncRun.default_per_page + 2).times { completed }

    get sync_runs_url

    assert_select "tbody tr", count: SyncRun.default_per_page
    assert_select "nav[aria-label=pager]"
  end

  test "index discloses the failures of a run that had them" do
    completed(state: :completed, errors: [ "broken.mp3: not audio" ])

    get sync_runs_url

    assert_select "details summary", text: /1 file could not be imported/
    assert_select "details li", text: /broken\.mp3: not audio/
  end

  test "index marks a forced run as a full rescan" do
    SyncRun.start!(forced: true)

    get sync_runs_url

    assert_select "tbody tr", text: /Full rescan/
  end

  test "index reports an abandoned run as interrupted" do
    run = SyncRun.start!
    run.update_column(:created_at, (ProgressReporting::STATUS_TTL + 1.minute).ago)

    get sync_runs_url

    assert_select "tbody tr", text: /Interrupted/
  end

  test "index has an empty state" do
    get sync_runs_url

    assert_response :success
    assert_select "h2", text: "No syncs yet"
  end

  test "the nav links to it" do
    get sync_runs_url

    assert_select "nav a[href=?]", sync_runs_path, text: "Sync history"
  end
end
