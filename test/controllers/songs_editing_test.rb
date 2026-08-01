require "test_helper"

class SongsEditingTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper

  test "edit renders the form inside the modal frame" do
    song = create_test_song("a.mp3", title: "Original")

    get edit_song_url(song)

    assert_response :success
    assert_select "turbo-frame#modal dialog"
    assert_select "input[name='song[title]'][value=Original]"
  end

  test "update saves the metadata" do
    song = create_test_song("a.mp3", title: "Before")

    patch song_url(song), params: { song: { title: "After", artist: "New Artist", year: 2001 } },
      as: :turbo_stream

    assert_response :success
    song.reload
    assert_equal "After", song.title
    assert_equal "New Artist", song.artist
    assert_equal 2001, song.year
  end

  test "update writes the new tags to the file" do
    song = create_test_song("a.mp3")

    patch song_url(song), params: { song: { title: "Written To Disk" } }, as: :turbo_stream

    assert_equal "Written To Disk", tags_on_disk(song.file_path)[:title]
  end

  test "update dismisses the modal and re-renders the list" do
    song = create_test_song("a.mp3")

    patch song_url(song), params: { song: { title: "Renamed" } }, as: :turbo_stream

    assert_select "turbo-stream[action=update][target=modal]"
    assert_select "turbo-stream[action=replace][target=songs]"
    assert_select "turbo-stream[action=append][target=toasts]"
  end

  test "update keeps the active filters when re-rendering the list" do
    create_test_song("a.mp3", title: "Keep", artist: "Alpha")
    other = create_test_song("b.mp3", title: "Other", artist: "Beta")

    patch song_url(other), params: {
      song: { title: "Renamed" },
      q: { artist_cont: "Alpha" }
    }, as: :turbo_stream

    # The re-rendered list is still filtered to Alpha, so the renamed Beta song
    # is absent rather than the filter being dropped.
    assert_select "turbo-stream[target=songs] td", text: "Keep"
    assert_select "turbo-stream[target=songs] td", text: "Renamed", count: 0
  end

  test "update keeps the current page" do
    51.times { |i| create_test_song("s#{i}.mp3", artist: "Alpha", title: format("Song %02d", i)) }
    song = Song.ordered.last

    patch song_url(song), params: { song: { title: "Renamed" }, page: 2 }, as: :turbo_stream

    assert_select "turbo-stream[target=songs] #songs_count", text: /page 2 of 2/
  end

  test "update re-renders the form with errors when the file cannot be written" do
    song = create_test_song("a.mp3")
    File.binwrite(song.file_path, "no longer valid audio")

    patch song_url(song), params: { song: { title: "Doomed" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "dialog [role=alert]", text: /Could not write tags/
    assert_equal "Test Song", song.reload.title
  end

  test "update only permits editable fields" do
    song = create_test_song("a.mp3")
    original_path = song.file_path

    patch song_url(song), params: { song: { title: "Fine", file_path: "/etc/passwd" } },
      as: :turbo_stream

    assert_equal original_path, song.reload.file_path
  end

  test "destroy removes the song and its file" do
    song = create_test_song("a.mp3")
    path = song.file_path

    assert_difference -> { Song.count }, -1 do
      delete song_url(song), as: :turbo_stream
    end

    assert_not File.exist?(path), "the file was left on disk"
  end

  test "destroy dismisses the modal, refreshes the list and reports success" do
    song = create_test_song("a.mp3")

    delete song_url(song), as: :turbo_stream

    assert_select "turbo-stream[action=update][target=modal]"
    assert_select "turbo-stream[action=replace][target=songs]"
    assert_select "turbo-stream[target=toasts]", text: /Deleted/
  end

  test "destroy keeps the active filters" do
    create_test_song("a.mp3", title: "Keep", artist: "Alpha")
    doomed = create_test_song("b.mp3", title: "Doomed", artist: "Beta")

    delete song_url(doomed), params: { q: { artist_cont: "Alpha" } }, as: :turbo_stream

    assert_select "turbo-stream[target=songs] td", text: "Keep"
    assert_select "turbo-stream[target=songs] #songs_count", text: /1 song/
  end

  test "destroy succeeds when the file is already gone" do
    song = create_test_song("a.mp3")
    File.delete(song.file_path)

    assert_difference -> { Song.count }, -1 do
      delete song_url(song), as: :turbo_stream
    end

    assert_response :success
  end

  test "the row links to the edit modal carrying the current filters" do
    create_test_song("a.mp3", artist: "Alpha")

    get songs_url(q: { artist_cont: "Alpha" })

    assert_select "td a[data-turbo-frame=modal]", text: "Edit"
    assert_select "td a[href*='artist_cont']"
  end
end
