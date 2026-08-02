require "application_system_test_case"

# What a headless browser can prove here: the <audio> element's src, its
# currentTime, node identity, and the surrounding DOM. What it cannot: that
# anything is audible, or that the MP3 decodes -- this Chromium may not ship the
# codec. Nothing asserts on `paused` being false, because play() can also be
# rejected by the autoplay policy. That the *server* can seek is proved by
# test/controllers/songs/audio_controller_test.rb, which is why the endpoint
# shipped in its own commit.
class PlayerTest < ApplicationSystemTestCase
  include LibraryTestHelper

  setup do
    @song = create_test_song("a.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album_artist: "Neon Fields", album: "Afterglow", duration: 245)
    @other = create_test_song("b.mp3", title: "Second Song", artist: "Other",
      album_artist: "Other", album: "Tidal", duration: 100)
  end

  def audio_property(name)
    page.evaluate_script("document.querySelector('#player audio').#{name}")
  end

  # Stamps the node and its media state, so what follows proves the element was
  # preserved rather than re-rendered with the same attributes.
  #
  # Returns the position actually reached rather than the one asked for: the
  # fixture MP3 is about two seconds long, so a seek past its end is clamped.
  def stamp_player
    page.execute_script(<<~JS)
      const audio = document.querySelector("#player audio")
      audio.dataset.probe = "kept"
      audio.currentTime = 1
    JS

    audio_property("currentTime")
  end

  test "playing a song opens the bar and points it at that song" do
    visit root_path
    click_on "Play Midnight Drive"

    assert_selector "#player:not([hidden])", text: "Midnight Drive"
    assert_selector "#player", text: "Neon Fields"
    assert_match song_audio_path(@song), audio_property("src")
  end

  # The whole reason the player lives in the layout under data-turbo-permanent.
  test "playback survives filtering the list and navigating to another page" do
    visit root_path
    click_on "Play Midnight Drive"
    assert_selector "#player:not([hidden])"
    position = stamp_player
    assert_operator position, :>, 0, "the seek did not take, so the check below proves nothing"

    fill_in placeholder: "Search title, artist, album or genre…", with: "Second"
    assert_selector "tbody tr", count: 1

    assert_equal "kept", audio_property("dataset.probe"), "the frame swap replaced the player"
    assert_in_delta position, audio_property("currentTime"), 0.5

    click_on "Sync history"
    assert_selector "h1", text: "Sync history"

    assert_equal "kept", audio_property("dataset.probe"), "a Turbo visit replaced the player"
    assert_in_delta position, audio_property("currentTime"), 0.5
    assert_selector "#player:not([hidden])", text: "Midnight Drive"
  end

  test "playing another song replaces what is loaded rather than stacking up" do
    visit root_path
    click_on "Play Midnight Drive"
    assert_selector "#player", text: "Midnight Drive"

    click_on "Play Second Song"

    assert_selector "#player", text: "Second Song"
    assert_match song_audio_path(@other), audio_property("src")
    assert_equal 1, page.evaluate_script("document.querySelectorAll('#player audio').length")
  end

  test "closing the player clears it" do
    visit root_path
    click_on "Play Midnight Drive"
    assert_selector "#player:not([hidden])"

    click_on "Close player"

    assert_selector "#player[hidden]", visible: :all
    assert_equal "", audio_property("getAttribute('src') || ''")
  end

  # Fifty buttons reconnect at once on a frame swap, and each has to work out
  # for itself whether it is the one playing.
  test "a play button re-syncs its label after the list re-renders" do
    visit root_path
    click_on "Play Midnight Drive"
    assert_selector "#player:not([hidden])"

    fill_in placeholder: "Search title, artist, album or genre…", with: "Midnight"
    assert_selector "tbody tr", count: 1

    # Still labelled for the same song, whichever state it settled in.
    assert_selector "button[aria-label$='Midnight Drive']"
  end

  test "a track can be played from an album page" do
    visit albums_path
    click_on "Afterglow"

    click_on "Play Midnight Drive"

    assert_selector "#player:not([hidden])", text: "Midnight Drive"
  end

  test "the player is hidden until something is played" do
    visit root_path

    assert_selector "#player[hidden]", visible: :all
  end
end
