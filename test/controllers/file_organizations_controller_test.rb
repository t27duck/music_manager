require "test_helper"

class FileOrganizationsControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper

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
    post file_organizations_url, params: {
      song_ids: [ @song.id ], template: PathTemplate::DEFAULT
    }, as: :turbo_stream

    assert_response :success
    expected = target("Neon Fields/Afterglow/07 - Midnight Drive.mp3")
    assert_equal expected, @song.reload.file_path
    assert File.exist?(expected)
  end

  test "create leaves songs outside the selection alone" do
    original = @other.file_path

    post file_organizations_url, params: {
      song_ids: [ @song.id ], template: PathTemplate::DEFAULT
    }, as: :turbo_stream

    assert_equal original, @other.reload.file_path
  end

  test "create dismisses the modal, refreshes the list and reports a summary" do
    post file_organizations_url, params: {
      song_ids: [ @song.id ], template: "<Artist>/<Title>"
    }, as: :turbo_stream

    assert_select "turbo-stream[action=update][target=modal]"
    assert_select "turbo-stream[action=replace][target=songs]"
    assert_select "turbo-stream[target=toasts]", text: /1 file moved/
  end

  test "create keeps the active filters when re-rendering the list" do
    post file_organizations_url, params: {
      song_ids: [ @song.id ],
      template: "<Artist>/<Title>",
      q: { title_contains: "Midnight" }
    }, as: :turbo_stream

    assert_select "turbo-stream[target=songs] #songs_count", text: /1 song/
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

  test "create remembers the template for next time" do
    post file_organizations_url, params: { song_ids: [ @song.id ], template: "<Genre>/<Title>" },
      as: :turbo_stream

    get new_file_organization_url(song_ids: [ @other.id ])

    assert_select "input[name=template][value='<Genre>/<Title>']"
    assert_equal "<Genre>/<Title>", Setting[:path_template]
  end

  # The reason the template is a Setting rather than session state: it is an app
  # preference, not something about this browser. reset! throws the session away.
  test "create remembers the template even for a new session" do
    post file_organizations_url, params: { song_ids: [ @song.id ], template: "<Genre>/<Title>" },
      as: :turbo_stream

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
    post file_organizations_url, params: {
      song_ids: [ @song.id, @other.id ], template: "<Album>/Track"
    }, as: :turbo_stream

    assert_select "turbo-stream[target=toasts]", text: /2 files moved/
    assert_not_equal @song.reload.file_path, @other.reload.file_path
  end

  test "the selection toolbar offers the organize action" do
    get songs_url

    assert_select "button[data-action='selection#organize']", text: "Organize files"
    assert_select "[data-selection-organize-url-value]"
  end
end
