require "test_helper"

class PathTemplateTest < ActiveSupport::TestCase
  include LibraryTestHelper

  setup do
    @song = create_test_song("original/name.mp3", title: "Midnight Drive", artist: "Neon Fields",
      album: "Afterglow", genre: "Synthwave", year: 2021, disc_number: 1, track_number: 7)
  end

  def render(template, song = @song)
    PathTemplate.new(template).render(song)
  end

  test "renders the text tokens" do
    assert_equal "Neon Fields.mp3", render("<Artist>")
    assert_equal "Afterglow.mp3", render("<Album>")
    assert_equal "Midnight Drive.mp3", render("<Title>")
    assert_equal "Synthwave.mp3", render("<Genre>")
  end

  test "renders the numeric tokens" do
    assert_equal "2021.mp3", render("<Year>")
    assert_equal "1.mp3", render("<Disc>")
    assert_equal "7.mp3", render("<Track>")
  end

  test "renders the original filename without its extension" do
    assert_equal "name.mp3", render("<Filename>")
  end

  test "zero-pads a numeric token to the requested width" do
    assert_equal "07.mp3", render("<Track:2>")
    assert_equal "007.mp3", render("<Track:3>")
    assert_equal "01.mp3", render("<Disc:2>")
  end

  test "builds nested directories" do
    assert_equal "Neon Fields/Afterglow/07 - Midnight Drive.mp3", render(PathTemplate::DEFAULT)
  end

  test "keeps the original extension" do
    song = create_test_song("shouty.MP3", title: "Loud")

    assert_equal "Loud.MP3", render("<Title>", song)
  end

  test "substitutes a placeholder for missing text" do
    song = create_test_song("bare.mp3", title: "Only Title", artist: nil, album: nil)

    assert_equal "Unknown Artist/Unknown Album/Only Title.mp3", render("<Artist>/<Album>/<Title>", song)
  end

  test "renders a missing number as nothing and tidies the leftovers" do
    song = create_test_song("bare.mp3", title: "No Track", track_number: nil)

    assert_equal "No Track.mp3", render("<Track:2> - <Title>", song)
  end

  test "drops a segment that renders empty rather than creating a nameless directory" do
    song = create_test_song("bare.mp3", title: "Kept", disc_number: nil)

    assert_equal "Kept.mp3", render("<Disc>/<Title>", song)
  end

  test "strips characters the filesystem rejects" do
    song = create_test_song("bare.mp3", title: 'AC/DC: Back? "Yes" *now*')

    assert_equal "ACDC Back Yes now.mp3", render("<Title>", song)
  end

  # A token value containing a slash must not silently become a directory.
  test "a slash inside a value does not create a directory" do
    song = create_test_song("bare.mp3", artist: "AC/DC", title: "Song")

    assert_equal "ACDC/Song.mp3", render("<Artist>/<Title>", song)
  end

  test "collapses whitespace and trims trailing dots" do
    song = create_test_song("bare.mp3", title: "Spaced    Out...")

    assert_equal "Spaced Out.mp3", render("<Title>", song)
  end

  test "does not produce a hidden file from a leading dot" do
    song = create_test_song("bare.mp3", title: ".hidden")

    assert_equal "hidden.mp3", render("<Title>", song)
  end

  test "literal text around tokens is kept" do
    assert_equal "Music/Neon Fields - Midnight Drive.mp3", render("Music/<Artist> - <Title>")
  end

  test "is invalid when blank" do
    template = PathTemplate.new("  ")

    assert_not_predicate template, :valid?
    assert_match(/can't be blank/, template.errors.to_sentence)
  end

  test "is invalid without any token" do
    template = PathTemplate.new("just some text")

    assert_not_predicate template, :valid?
    assert_match(/at least one token/, template.errors.to_sentence)
  end

  test "rejects unknown tokens" do
    template = PathTemplate.new("<Artist>/<Nonsense>")

    assert_not_predicate template, :valid?
    assert_match(/<Nonsense>/, template.errors.to_sentence)
  end

  test "rejects a template that tries to climb out of the library" do
    template = PathTemplate.new("../<Title>")

    assert_not_predicate template, :valid?
    assert_match(/\.\./, template.errors.to_sentence)
  end

  test "rejects an absolute template" do
    template = PathTemplate.new("/etc/<Title>")

    assert_not_predicate template, :valid?
    assert_match(/slash/, template.errors.to_sentence)
  end

  test "rendering an invalid template raises" do
    assert_raises(PathTemplate::Error) { render("no tokens here") }
  end

  test "the default template is valid" do
    assert_predicate PathTemplate.new(PathTemplate::DEFAULT), :valid?
  end
end
