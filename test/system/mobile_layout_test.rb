require "application_system_test_case"

# The song table reflowed into one card per song on a phone.
#
# Everything here runs at 390x844; the rest of the suite runs at 1400x1400 and
# so exercises the table layout. That split is the point of reflowing with CSS
# rather than emitting two markup trees -- both layouts are the same elements
# with the same dom_ids, so neither set of tests has to know about the other.
class MobileLayoutTest < ApplicationSystemTestCase
  include LibraryTestHelper

  PHONE = [ 390, 844 ].freeze
  DESKTOP = [ 1400, 1400 ].freeze

  setup do
    @song = create_test_song("a.mp3",
      title: "Amish Paradise (Parody of 'Gangsta's Paradise' by Coolio)",
      artist: "Weird Al Yankovic", album: "Bad Hair Day", genre: "Parody",
      year: 1996, track_number: 1, duration: 201)
    @other = create_test_song("b.mp3", title: "Zebra", artist: "ZZZ", genre: "Rock")

    page.current_window.resize_to(*PHONE)
  end

  # Not optional: Selenium reuses the browser between tests and Capybara's
  # session reset does not restore the window size. Without this every test
  # that ran afterwards would silently be a phone test.
  teardown { page.current_window.resize_to(*DESKTOP) }

  def display_of(selector)
    evaluate_script("getComputedStyle(document.querySelector('#{selector}')).display")
  end

  test "rows become cards and the header is hidden" do
    visit root_path

    assert_equal "grid", display_of("tbody tr")
    assert_equal "none", display_of("thead")
  end

  # The actual complaint: a phone had to scroll sideways to read the library.
  test "the page does not scroll sideways" do
    visit root_path

    assert evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"),
      "the page scrolls horizontally at #{PHONE.first}px"
  end

  test "a card shows the song's key fields" do
    visit root_path

    within "##{dom_id(@song)}" do
      assert_text "Amish Paradise"
      assert_text "Weird Al Yankovic"
      assert_text "Bad Hair Day"
      assert_text "Parody"
      assert_text "1996"
      assert_text "3:21"
    end
  end

  test "songs can still be selected and edited from a card" do
    visit root_path

    find("##{dom_id(@song, :select)}").check
    assert_text "1 selected"

    within("##{dom_id(@song)}") { click_on "Edit" }
    assert_selector "dialog h2", text: "Edit song"
  end

  # The column headers are the only way to sort on a wide screen, and they are
  # hidden here, so the select in the filter panel stands in for them.
  test "the list can be sorted without the column headers" do
    visit root_path

    find("summary", text: "Advanced filters").click
    select "Title Z–A", from: "Sort"

    assert_selector "tbody tr:first-child", text: "Zebra"
  end

  test "inline editing still works on a card" do
    visit root_path

    find("#genre_song_#{@other.id}").double_click
    assert_selector "#genre_song_#{@other.id} input"

    find("#genre_song_#{@other.id} input").set("Synthwave")
    find("#genre_song_#{@other.id} input").send_keys(:enter)

    assert_selector "#genre_song_#{@other.id}", text: "Synthwave"
    assert_equal "Synthwave", @other.reload.genre
  end

  test "the table layout returns at desktop width" do
    visit root_path
    assert_equal "grid", display_of("tbody tr")

    page.current_window.resize_to(*DESKTOP)

    assert_equal "table-row", display_of("tbody tr")
    assert_equal "table-header-group", display_of("thead")
  end
end
