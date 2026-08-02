require "test_helper"

class FileOrganizationsControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper
  include ActiveJob::TestHelper

  setup do
    @song = create_test_song("loose/one.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album: "Afterglow", track_number: 7)
    @other = create_test_song("loose/two.mp3", title: "Untouched", artist: "Someone Else")
  end

  def target(*parts) = File.join(@temp_dir, *parts)

  test "new renders the template form and a preview" do
    get new_file_organization_url(song_ids: [ @song.id ])

    assert_response :success
    assert_select "turbo-frame#modal dialog h2", text: "Organize 1 file"
    assert_select "input[name=template][value=?]", PathTemplate::DEFAULT
    assert_select "turbo-frame#file_organization_preview", text: /Neon Fields\/Afterglow\/07 - Midnight Drive\.mp3/
  end

  test "new previews the template as it is typed" do
    get new_file_organization_url(song_ids: [ @song.id ], template: "<Genre>/<Title>")

    assert_select "turbo-frame#file_organization_preview", text: /Unknown Genre\/Midnight Drive\.mp3/
  end

  test "new reports an invalid template without failing" do
    get new_file_organization_url(song_ids: [ @song.id ], template: "no tokens")

    assert_response :success
    assert_select "[role=alert]", text: /at least one token/
  end

  # Real music filenames are long. The preview must render the destination in
  # full -- it is the decision the user is making.
  test "new shows the whole destination path for a long filename" do
    song = create_test_song("loose/x.mp3",
      title: "Amish Paradise (Parody of 'Gangsta's Paradise' by Coolio)",
      artist: "Weird Al Yankovic", album: "Bad Hair Day", track_number: 1)

    get new_file_organization_url(song_ids: [ song.id ])

    assert_select "turbo-frame#file_organization_preview", text: %r{
      Weird\ Al\ Yankovic/Bad\ Hair\ Day/01\ -\ Amish\ Paradise\ \(Parody\ of\ 'Gangsta's\ Paradise'\ by\ Coolio\)\.mp3
    }x
  end

  test "new only previews the selection" do
    get new_file_organization_url(song_ids: [ @song.id ])

    assert_select "turbo-frame#file_organization_preview", text: /Midnight Drive/
    assert_select "turbo-frame#file_organization_preview", text: /Untouched/, count: 0
  end

  test "create moves the selected files" do
    perform_enqueued_jobs do
      post file_organizations_url, params: {
        song_ids: [ @song.id ], template: PathTemplate::DEFAULT
      }, as: :turbo_stream
    end

    assert_response :success
    expected = target("Neon Fields/Afterglow/07 - Midnight Drive.mp3")
    assert_equal expected, @song.reload.file_path
    assert File.exist?(expected)
  end

  test "create leaves songs outside the selection alone" do
    original = @other.file_path

    perform_enqueued_jobs do
      post file_organizations_url, params: {
        song_ids: [ @song.id ], template: PathTemplate::DEFAULT
      }, as: :turbo_stream
    end

    assert_equal original, @other.reload.file_path
  end

  # The list is deliberately not replaced here -- nothing has moved yet. The
  # refresh arrives from progress/_update once the job finishes, which reloads
  # each viewer's own URL and so preserves their filters.
  test "create dismisses the modal and says the work has started" do
    post file_organizations_url, params: {
      song_ids: [ @song.id ], template: "<Artist>/<Title>"
    }, as: :turbo_stream

    assert_select "turbo-stream[action=update][target=modal]"
    assert_select "turbo-stream[target=toasts]", text: /Organizing 1 file/
    assert_select "turbo-stream[target=songs]", false
  end

  test "create enqueues the job with the selection resolved to ids" do
    assert_enqueued_with(job: FileOrganizationJob,
      args: [ { song_ids: [ @song.id ], template: "<Artist>/<Title>" } ]) do
      post file_organizations_url, params: {
        song_ids: [ @song.id ], template: "<Artist>/<Title>"
      }, as: :turbo_stream
    end
  end

  test "create refuses to start while something else is running" do
    LibrarySync.publish(LibrarySync::Status.starting)

    assert_no_enqueued_jobs(only: FileOrganizationJob) do
      post file_organizations_url, params: {
        song_ids: [ @song.id ], template: "<Artist>/<Title>"
      }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /already running/
  end

  test "create refuses an invalid template" do
    original = @song.file_path

    post file_organizations_url, params: { song_ids: [ @song.id ], template: "no tokens" },
      as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /at least one token/
    assert_equal original, @song.reload.file_path
  end

  test "create refuses a template that escapes the library" do
    original = @song.file_path

    post file_organizations_url, params: { song_ids: [ @song.id ], template: "../<Title>" },
      as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal original, @song.reload.file_path
  end

  test "create refuses an empty selection" do
    post file_organizations_url, params: { template: PathTemplate::DEFAULT }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Select some songs/
  end

  # The template is remembered by the job, once the moves have actually happened.
  test "create remembers the template for next time" do
    perform_enqueued_jobs do
      post file_organizations_url, params: { song_ids: [ @song.id ], template: "<Genre>/<Title>" },
        as: :turbo_stream
    end

    get new_file_organization_url(song_ids: [ @other.id ])

    assert_select "input[name=template][value='<Genre>/<Title>']"
    assert_equal "<Genre>/<Title>", Setting[:path_template]
  end

  # The reason the template is a Setting rather than session state: it is an app
  # preference, not something about this browser. reset! throws the session away.
  test "create remembers the template even for a new session" do
    perform_enqueued_jobs do
      post file_organizations_url, params: { song_ids: [ @song.id ], template: "<Genre>/<Title>" },
        as: :turbo_stream
    end

    reset!

    get new_file_organization_url(song_ids: [ @other.id ])

    assert_select "input[name=template][value='<Genre>/<Title>']"
  end

  test "new falls back to the default template when nothing has been applied yet" do
    get new_file_organization_url(song_ids: [ @song.id ])

    assert_select "input[name=template][value='#{PathTemplate::DEFAULT}']"
  end

  test "create reports failures alongside successes" do
    # Both songs render to the same name; the second is suffixed, not lost.
    perform_enqueued_jobs do
      post file_organizations_url, params: {
        song_ids: [ @song.id, @other.id ], template: "<Album>/Track"
      }, as: :turbo_stream
    end

    assert_equal "2 files moved.", FileOrganization.status.summary
    assert_not_equal @song.reload.file_path, @other.reload.file_path
  end

  test "the selection toolbar offers the organize action" do
    get songs_url

    assert_select "button[data-action='selection#organize']", text: "Organize files"
    assert_select "[data-selection-organize-url-value]"
  end
end
