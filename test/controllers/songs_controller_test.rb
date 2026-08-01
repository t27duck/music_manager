require "test_helper"

class SongsControllerTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper

  test "renders the empty state when the library has no songs" do
    get songs_url

    assert_response :success
    assert_select "h2", text: "Your library is empty"
    assert_select "table", count: 0
  end

  test "lists songs" do
    create_test_song("a.mp3", title: "First Song", artist: "Alpha", album: "One")

    get songs_url

    assert_response :success
    assert_select "td", text: "First Song"
    assert_select "td", text: "Alpha"
  end

  test "the root route is the song index" do
    get root_url

    assert_response :success
    assert_select "h1", text: "Songs"
  end

  test "shows the song count" do
    create_test_song("a.mp3")
    create_test_song("b.mp3")

    get songs_url

    assert_select "#songs_count", text: /2 songs/
  end

  test "uses the singular when there is one song" do
    create_test_song("a.mp3")

    get songs_url

    assert_select "#songs_count", text: /1 song(?!s)/
  end

  test "orders songs by artist, album, disc and track" do
    create_test_song("b.mp3", title: "Second", artist: "Alpha", album: "A", track_number: 2)
    create_test_song("a.mp3", title: "First", artist: "Alpha", album: "A", track_number: 1)

    get songs_url

    titles = css_select("tbody turbo-frame[id^='title_song_']").map { |cell| cell.text.strip }
    assert_equal [ "First", "Second" ], titles
  end

  test "paginates at 50 songs per page" do
    51.times { |i| create_test_song("song#{i}.mp3", artist: "Artist", title: format("Song %02d", i)) }

    get songs_url

    assert_select "tbody tr", count: 50
    assert_select "nav[aria-label=pager]"
  end

  test "serves the second page" do
    51.times { |i| create_test_song("song#{i}.mp3", artist: "Artist", title: format("Song %02d", i)) }

    get songs_url(page: 2)

    assert_select "tbody tr", count: 1
    assert_select "#songs_count", text: /page 2 of 2/
  end

  test "does not paginate a single page of results" do
    create_test_song("a.mp3")

    get songs_url

    assert_select "nav[aria-label=pager]", count: 0
  end

  test "renders the song list inside a turbo frame so filters can replace it" do
    create_test_song("a.mp3")

    get songs_url

    assert_select "turbo-frame#songs"
  end
end
