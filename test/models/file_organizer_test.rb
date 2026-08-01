require "test_helper"

class FileOrganizerTest < ActiveSupport::TestCase
  include LibraryTestHelper

  def organizer(template = PathTemplate::DEFAULT)
    FileOrganizer.new(template, root: @temp_dir)
  end

  def path(*parts) = File.join(@temp_dir, *parts)

  test "previews where each song would go" do
    song = create_test_song("loose.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album: "Afterglow", track_number: 7)

    move = organizer.preview([ song ]).sole

    assert_equal song.file_path, move.from
    assert_equal path("Neon Fields/Afterglow/07 - Midnight Drive.mp3"), move.to
    assert_predicate move, :moving?
  end

  test "preview does not touch the filesystem" do
    song = create_test_song("loose.mp3", title: "Stays Put")

    organizer("<Title>").preview([ song ])

    assert File.exist?(song.file_path)
    assert_equal 1, Dir.glob("#{@temp_dir}/**/*.mp3").size
  end

  test "a song already in place is reported as unchanged" do
    song = create_test_song("Neon Fields/Afterglow/07 - Midnight Drive.mp3",
      title: "Midnight Drive", artist: "Neon Fields", album: "Afterglow", track_number: 7)

    move = organizer.preview([ song ]).sole

    assert_predicate move, :unchanged?
    assert_not_predicate move, :moving?
  end

  test "applies the moves and updates the records" do
    song = create_test_song("loose.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album: "Afterglow", track_number: 7)

    result = organizer.apply!([ song ])

    expected = path("Neon Fields/Afterglow/07 - Midnight Drive.mp3")
    assert_equal 1, result.moved_count
    assert File.exist?(expected)
    assert_equal expected, song.reload.file_path
  end

  test "creates the directories it needs" do
    song = create_test_song("loose.mp3", title: "Deep", artist: "A", album: "B")

    organizer("<Artist>/<Album>/<Title>").apply!([ song ])

    assert Dir.exist?(path("A/B"))
  end

  test "removes directories the move emptied" do
    song = create_test_song("Old/Nested/loose.mp3", title: "Moved", artist: "A")

    organizer("<Artist>/<Title>").apply!([ song ])

    assert_not Dir.exist?(path("Old/Nested"))
    assert_not Dir.exist?(path("Old"))
    assert Dir.exist?(@temp_dir), "the library root itself was removed"
  end

  test "leaves a directory that still holds other files" do
    keeper = create_test_song("Old/keeper.mp3", title: "Keeper")
    mover = create_test_song("Old/mover.mp3", title: "Mover", artist: "A")

    FileOrganizer.new("<Artist>/<Title>", root: @temp_dir).apply!([ mover ])

    assert Dir.exist?(path("Old"))
    assert File.exist?(keeper.file_path)
  end

  test "suffixes a name that two songs would share" do
    first = create_test_song("a.mp3", title: "Same", artist: "A")
    second = create_test_song("b.mp3", title: "Same", artist: "A")

    organizer("<Artist>/<Title>").apply!([ first, second ])

    assert_equal path("A/Same.mp3"), first.reload.file_path
    assert_equal path("A/Same (2).mp3"), second.reload.file_path
    assert File.exist?(first.file_path)
    assert File.exist?(second.file_path)
  end

  test "suffixes around an unrelated file already sitting there" do
    FileUtils.mkdir_p(path("A"))
    File.write(path("A/Same.mp3"), "not ours")
    song = create_test_song("a.mp3", title: "Same", artist: "A")

    organizer("<Artist>/<Title>").apply!([ song ])

    assert_equal path("A/Same (2).mp3"), song.reload.file_path
    assert_equal "not ours", File.read(path("A/Same.mp3"))
  end

  test "the preview shows the suffixed name that will actually be used" do
    create_test_song("a.mp3", title: "Same", artist: "A")
    second = create_test_song("b.mp3", title: "Same", artist: "A")

    moves = organizer("<Artist>/<Title>").preview(Song.in_library(@temp_dir).ordered.to_a)

    assert_equal [ path("A/Same.mp3"), path("A/Same (2).mp3") ], moves.map(&:to)
    assert_not_equal moves.first.to, second.file_path
  end

  test "reports an invalid template per song rather than blowing up" do
    song = create_test_song("a.mp3")

    move = organizer("no tokens").preview([ song ]).sole

    assert_predicate move, :failed?
    assert_match(/at least one token/, move.error)
  end

  test "does not move a file when the record cannot be saved" do
    song = create_test_song("a.mp3", title: "Blocked", artist: "A")
    original_path = song.file_path
    other = create_test_song("b.mp3", title: "Existing")
    # Force a uniqueness collision on file_path.
    other.update_column(:file_path, File.join(@temp_dir, "A", "Blocked.mp3"))

    result = organizer("<Artist>/<Title>").apply!([ song ])

    assert_equal 1, result.failure_count
    assert File.exist?(original_path), "the file moved even though the record did not save"
    assert_equal original_path, song.reload.file_path
    assert_equal original_path, song.file_path, "the failed path was left on the in-memory record"
  end

  test "summarises what happened" do
    moved = create_test_song("a.mp3", title: "Moved", artist: "A")
    create_test_song("A/Still.mp3", title: "Still", artist: "A")

    result = organizer("<Artist>/<Title>").apply!(Song.in_library(@temp_dir).ordered.to_a)

    assert_equal "1 file moved, 1 already in place.", result.summary
    assert_equal moved.reload.file_path, path("A/Moved.mp3")
  end

  test "does not write the files' tags while moving them" do
    song = create_test_song("a.mp3", title: "Untouched Tags", artist: "A")
    original = tags_on_disk(song.file_path)

    organizer("<Artist>/<Title>").apply!([ song ])

    assert_equal original[:title], tags_on_disk(song.reload.file_path)[:title]
  end

  test "an empty selection is a no-op" do
    result = organizer.apply!([])

    assert_equal 0, result.moved_count
    assert_not_predicate result, :any_failures?
  end
end
