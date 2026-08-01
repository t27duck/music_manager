require "test_helper"

class SongsHelperTest < ActionView::TestCase
  test "formats durations under an hour as minutes and seconds" do
    assert_equal "0:07", formatted_duration(7)
    assert_equal "2:34", formatted_duration(154)
    assert_equal "59:59", formatted_duration(3599)
  end

  test "formats durations of an hour or more with hours" do
    assert_equal "1:00:00", formatted_duration(3600)
    assert_equal "1:02:05", formatted_duration(3725)
  end

  test "formats a blank duration as a dash" do
    assert_equal "—", formatted_duration(nil)
  end

  test "formats file sizes" do
    assert_equal "1 KB", formatted_file_size(1024)
    assert_equal "—", formatted_file_size(nil)
  end

  test "formats a track number on its own when there is no disc" do
    song = Song.new(track_number: 4)

    assert_equal "4", formatted_track(song)
  end

  test "combines disc and track numbers" do
    song = Song.new(disc_number: 2, track_number: 4)

    assert_equal "2-4", formatted_track(song)
  end

  test "formats a missing track number as a dash" do
    assert_equal "—", formatted_track(Song.new)
  end

  test "renders missing metadata as a muted dash" do
    assert_equal "Rock", metadata_value("Rock")
    assert_match(/text-surface-600/, metadata_value(nil))
    assert_match(/—/, metadata_value(""))
  end
end
