require "test_helper"

class BulkUpdatesControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper
  include ActiveJob::TestHelper

  setup do
    @one = create_test_song("a.mp3", title: "One", artist: "Old Artist")
    @two = create_test_song("b.mp3", title: "Two", artist: "Old Artist")
    @untouched = create_test_song("c.mp3", title: "Three", artist: "Old Artist")
  end

  def selected = [ @one.id, @two.id ]

  test "new renders the bulk form for the selection" do
    get new_bulk_update_url(song_ids: selected)

    assert_response :success
    assert_select "turbo-frame#modal dialog h2", text: "Edit 2 songs"
    assert_select "input[name='song_ids[]']", count: 2
  end

  test "new lists the selected songs so the user can check them" do
    get new_bulk_update_url(song_ids: selected)

    assert_select "dialog", text: /One/
    assert_select "dialog", text: /Two/
    assert_select "dialog", text: /Three/, count: 0
  end

  test "create applies the changes to the selection only" do
    perform_enqueued_jobs do
      post bulk_updates_url, params: { song_ids: selected, bulk_update: { artist: "New Artist" } },
        as: :turbo_stream
    end

    assert_response :success
    assert_equal "New Artist", @one.reload.artist
    assert_equal "New Artist", @two.reload.artist
    assert_equal "Old Artist", @untouched.reload.artist
  end

  test "create writes the changes to the files" do
    perform_enqueued_jobs do
      post bulk_updates_url, params: { song_ids: selected, bulk_update: { genre: "Ambient" } },
        as: :turbo_stream
    end

    assert_equal "Ambient", tags_on_disk(@one.file_path)[:genre]
  end

  # The list is deliberately not replaced here -- nothing has changed yet. The
  # refresh arrives from progress/_update once the job finishes, which reloads
  # each viewer's own URL and so preserves their filters.
  test "create dismisses the modal and says the work has started" do
    post bulk_updates_url, params: { song_ids: selected, bulk_update: { artist: "New Artist" } },
      as: :turbo_stream

    assert_select "turbo-stream[action=update][target=modal]"
    assert_select "turbo-stream[target=toasts]", text: /Updating 2 songs/
    assert_select "turbo-stream[target=songs]", false
  end

  test "create enqueues the job with the selection resolved to ids" do
    assert_enqueued_with(job: BulkEditJob) do
      post bulk_updates_url, params: { song_ids: selected, bulk_update: { artist: "New Artist" } },
        as: :turbo_stream
    end
  end

  test "create refuses to start while something else is running" do
    LibrarySync.publish(LibrarySync::Status.starting)

    assert_no_enqueued_jobs(only: BulkEditJob) do
      post bulk_updates_url, params: { song_ids: selected, bulk_update: { artist: "New Artist" } },
        as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /already running/
  end

  test "create assigns album art to the selection" do
    perform_enqueued_jobs do
      post bulk_updates_url, params: {
        song_ids: selected,
        album_art: fixture_file_upload("cover.jpg", "image/jpeg")
      }, as: :turbo_stream
    end

    assert_predicate @one.reload, :album_art?
    assert_predicate @two.reload, :album_art?
  end

  test "create can remove album art across the selection" do
    cover = File.binread(fixture_file("cover.jpg"))
    [ @one, @two ].each { |song| song.update_album_art!(cover) }

    perform_enqueued_jobs do
      post bulk_updates_url, params: { song_ids: selected, remove_album_art: "1" }, as: :turbo_stream
    end

    assert_not_predicate @one.reload, :album_art?
    assert_not_predicate @two.reload, :album_art?
  end

  test "create reports partial failures without losing the successes" do
    File.binwrite(@two.file_path, "no longer valid audio")

    perform_enqueued_jobs do
      post bulk_updates_url, params: { song_ids: selected, bulk_update: { artist: "New Artist" } },
        as: :turbo_stream
    end

    assert_equal "New Artist", @one.reload.artist
    assert_equal "1 song updated, 1 failed.", BulkEdit.status.summary
    assert_match(/Could not write tags/, BulkEdit.status.errors.first)
  end

  test "create refuses a submission with no changes" do
    post bulk_updates_url, params: { song_ids: selected, bulk_update: { artist: "" } },
      as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /at least one change/
    assert_equal "Old Artist", @one.reload.artist
  end

  test "create refuses an empty selection" do
    post bulk_updates_url, params: { bulk_update: { artist: "New Artist" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal "Old Artist", @one.reload.artist
  end

  test "create ignores fields that are not offered in bulk" do
    perform_enqueued_jobs do
      post bulk_updates_url, params: {
        song_ids: [ @one.id ],
        bulk_update: { title: "Renamed", file_path: "/etc/passwd", artist: "Fine" }
      }, as: :turbo_stream
    end

    @one.reload
    assert_equal "One", @one.title
    assert_equal "Fine", @one.artist
    assert_not_equal "/etc/passwd", @one.file_path
  end

  test "the song list renders selection checkboxes" do
    get songs_url

    assert_select "input[type=checkbox][name='song_ids[]']", count: 3
    assert_select "input[type=checkbox][data-selection-target=toggleAll]"
  end

  test "the selection toolbar starts hidden" do
    get songs_url

    assert_select "[data-selection-target=actions][hidden]"
  end
end
