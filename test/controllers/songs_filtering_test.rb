require "test_helper"

class SongsFilteringTest < ActionDispatch::IntegrationTest
  include LibraryTestHelper

  def titles_on_page
    # Target the title cell by its frame id rather than by column position,
    # which changes whenever a column is added.
    css_select("tbody turbo-frame[id^='title_song_']").map { |cell| cell.text.strip }
  end

  test "the global search narrows the list" do
    create_test_song("a.mp3", title: "Midnight Drive")
    create_test_song("b.mp3", title: "Morning Light")

    get songs_url(q: { text_contains: "Midnight" })

    assert_equal [ "Midnight Drive" ], titles_on_page
    assert_select "#songs_count", text: /1 song/
  end

  test "the global search covers artist, album and genre too" do
    create_test_song("a.mp3", title: "One", artist: "Neon Fields")
    create_test_song("b.mp3", title: "Two", album: "Neon Nights")
    create_test_song("c.mp3", title: "Three", genre: "Neon Pop")
    create_test_song("d.mp3", title: "Four", artist: "Other")

    get songs_url(q: { text_contains: "Neon" })

    assert_equal 3, titles_on_page.size
  end

  test "filters by individual fields" do
    create_test_song("a.mp3", title: "Keep", artist: "Alpha", album: "One", genre: "Rock", year: 1999)
    create_test_song("b.mp3", title: "Drop", artist: "Beta", album: "Two", genre: "Jazz", year: 2005)

    get songs_url(q: { artist_contains: "Alpha" })
    assert_equal [ "Keep" ], titles_on_page

    get songs_url(q: { album_contains: "One" })
    assert_equal [ "Keep" ], titles_on_page

    get songs_url(q: { genre_contains: "Rock" })
    assert_equal [ "Keep" ], titles_on_page

    get songs_url(q: { year_eq: 1999 })
    assert_equal [ "Keep" ], titles_on_page
  end

  test "combines multiple filters at once" do
    create_test_song("a.mp3", title: "Both", artist: "Alpha", genre: "Jazz")
    create_test_song("b.mp3", title: "Artist only", artist: "Alpha", genre: "Rock")
    create_test_song("c.mp3", title: "Genre only", artist: "Beta", genre: "Jazz")

    get songs_url(q: { artist_contains: "Alpha", genre_contains: "Jazz" })

    assert_equal [ "Both" ], titles_on_page
  end

  test "the file path filter escapes underscores" do
    create_test_song("my_song.mp3", title: "Literal")
    create_test_song("myXsong.mp3", title: "Wildcard")

    get songs_url(q: { file_path_contains: "my_song" })

    assert_equal [ "Literal" ], titles_on_page
  end

  test "the title filter escapes underscores" do
    create_test_song("a.mp3", title: "my_song")
    create_test_song("b.mp3", title: "myXsong")

    get songs_url(q: { title_contains: "my_song" })

    assert_equal [ "my_song" ], titles_on_page
  end

  test "the global search escapes underscores" do
    create_test_song("a.mp3", title: "Literal", album: "my_album")
    create_test_song("b.mp3", title: "Wildcard", album: "myXalbum")

    get songs_url(q: { text_contains: "my_album" })

    assert_equal [ "Literal" ], titles_on_page
  end

  # Ransack used to coerce these single characters into booleans, which raised
  # ArgumentError for "t" and silently dropped the filter for "0".
  test "a one-character search Ransack would read as a boolean still filters" do
    create_test_song("t.mp3", title: "t")
    create_test_song("other.mp3", title: "Zebra")

    get songs_url(q: { title_contains: "t" })
    assert_response :success
    assert_equal [ "t" ], titles_on_page

    get songs_url(q: { file_path_contains: "t.mp3" })
    assert_response :success
    assert_equal [ "t" ], titles_on_page
  end

  test "filters by missing metadata" do
    create_test_song("a.mp3", title: "No artist", artist: nil)
    create_test_song("b.mp3", title: "Has artist", artist: "Someone")

    get songs_url(q: { missing_metadata: "artist" })

    assert_equal [ "No artist" ], titles_on_page
  end

  test "sorts by any column" do
    create_test_song("a.mp3", title: "Bravo", artist: "Z")
    create_test_song("b.mp3", title: "Alpha", artist: "Y")

    get songs_url(q: { s: "title asc" })
    assert_equal [ "Alpha", "Bravo" ], titles_on_page

    get songs_url(q: { s: "title desc" })
    assert_equal [ "Bravo", "Alpha" ], titles_on_page
  end

  test "falls back to the natural library order when nothing is sorted" do
    create_test_song("b.mp3", title: "Second", artist: "A", album: "A", track_number: 2)
    create_test_song("a.mp3", title: "First", artist: "A", album: "A", track_number: 1)

    get songs_url

    assert_equal [ "First", "Second" ], titles_on_page
  end

  test "renders sortable column headings" do
    create_test_song("a.mp3")

    get songs_url

    # Ransack URL-encodes the bracketed param name: q%5Bs%5D is q[s].
    assert_select "th a[href*='q%5Bs%5D=title']"
    assert_select "th a[href*='q%5Bs%5D=artist']"
    assert_select "th a[data-turbo-frame=songs]", minimum: 5
  end

  test "shows a no-results state when filters match nothing" do
    create_test_song("a.mp3", title: "Something")

    get songs_url(q: { title_contains: "nothing matches this" })

    assert_select "h2", text: "No songs match your filters"
    assert_select "h2", text: "Your library is empty", count: 0
  end

  test "shows the empty-library state when there are no songs and no filters" do
    get songs_url

    assert_select "h2", text: "Your library is empty"
  end

  test "keeps filter values in the form so they survive a reload" do
    create_test_song("a.mp3", artist: "Alpha")

    get songs_url(q: { artist_contains: "Alpha" })

    assert_select "input[name='q[artist_contains]'][value=Alpha]"
  end

  test "opens the advanced panel when an advanced filter is active" do
    create_test_song("a.mp3")

    get songs_url(q: { artist_contains: "Alpha" })
    assert_select "details[open]"

    get songs_url
    assert_select "details[open]", count: 0
  end

  test "shows the reset link only while filters are active" do
    create_test_song("a.mp3")

    get songs_url(q: { artist_contains: "Alpha" })
    assert_select "a[hidden]", count: 0

    get songs_url
    assert_select "a[hidden]"
  end

  test "paginates filtered results" do
    51.times { |i| create_test_song("s#{i}.mp3", artist: "Alpha", title: format("Song %02d", i)) }
    create_test_song("other.mp3", artist: "Beta", title: "Excluded")

    get songs_url(q: { artist_contains: "Alpha" })

    assert_select "tbody tr", count: 50
    assert_select "#songs_count", text: /51 songs/
  end

  test "pagination links carry the filters" do
    51.times { |i| create_test_song("s#{i}.mp3", artist: "Alpha", title: format("Song %02d", i)) }

    get songs_url(q: { artist_contains: "Alpha" })

    assert_select "nav[aria-label=pager] a[href*='artist_contains']"
  end

  test "ignores unknown query keys instead of raising" do
    create_test_song("a.mp3")

    get songs_url(q: { nonsense_cont: "x" })

    assert_response :success
  end
end
