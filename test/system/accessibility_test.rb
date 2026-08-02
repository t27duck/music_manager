require "application_system_test_case"

# Guards the accessibility basics that are easy to lose in a refactor: a control
# that stops being reachable or nameable is not something the other system tests
# would notice.
class AccessibilityTest < ApplicationSystemTestCase
  include LibraryTestHelper

  setup do
    3.times do |i|
      create_test_song("s#{i}.mp3", title: "Song #{i}", artist: "Artist #{i}", album: "Album")
    end
  end

  def unnamed_controls
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("a, button, input, select"))
        .filter((el) => el.type !== "hidden" && el.offsetParent !== null)
        .filter((el) => !(el.getAttribute("aria-label") || el.textContent.trim() ||
                          (el.labels && el.labels.length) || el.title ||
                          el.getAttribute("placeholder")))
        .map((el) => `${el.tagName}.${el.className}`)
    JS
  end

  test "every visible control on the song list has an accessible name" do
    visit root_path
    assert_text "3 songs"

    assert_empty unnamed_controls
  end

  test "every visible control on the upload page has an accessible name" do
    visit upload_path

    assert_empty unnamed_controls
  end

  test "every visible control on the album pages has an accessible name" do
    visit albums_path
    assert_selector "li"
    assert_empty unnamed_controls

    first("li a").click
    assert_selector "tbody tr"
    assert_empty unnamed_controls
  end

  test "every album cover has alt text" do
    visit albums_path

    assert_equal 0,
      page.evaluate_script("Array.from(document.querySelectorAll('img')).filter(i => !i.alt).length")
  end

  test "every album art image has alt text" do
    visit root_path

    assert_equal 0, page.evaluate_script("Array.from(document.querySelectorAll('img')).filter(i => !i.alt).length")
  end

  test "the song table is named for screen readers" do
    visit root_path

    assert_selector "table[aria-label=Songs]"
  end

  test "filter results and sync progress are announced" do
    visit root_path

    assert_selector "#songs_count[aria-live=polite]"
    assert_selector "#progress[aria-live=polite]"
    assert_selector "#toasts[aria-live=polite]"
  end

  test "a skip link jumps past the navigation" do
    visit root_path

    skip_link = find("a", text: "Skip to content", visible: :all)
    assert_equal "#main", skip_link[:href].sub(%r{\A.*(?=#)}, "")
    assert_selector "main#main"
  end

  test "each page has exactly one level-one heading" do
    [ root_path, upload_path, albums_path, artists_path, sync_runs_path ].each do |path|
      visit path
      assert_selector "h1", count: 1
    end
  end

  test "the sync progress bar reports its value" do
    LibrarySync.publish(
      LibrarySync::Status.new(state: :running, current: 3, total: 10,
        filename: "track.mp3", errors: [], finished_at: nil, skipped: 0)
    )

    visit root_path

    assert_selector "[role=progressbar][aria-valuenow='30'][aria-valuemin='0'][aria-valuemax='100']"
  end

  test "row checkboxes name the song they select" do
    visit root_path

    assert_selector "input[type=checkbox][aria-label='Select Song 0']"
    assert_selector "input[type=checkbox][aria-label='Select all songs on this page']"
  end
end
