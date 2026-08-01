require "test_helper"

class LibraryScannerTest < ActiveSupport::TestCase
  include LibraryTestHelper

  test "finds MP3s at the top level and in subdirectories" do
    copy_fixture("top.mp3")
    copy_fixture("Artist/Album/nested.mp3")

    paths = LibraryScanner.new(@temp_dir).mp3_paths

    assert_equal 2, paths.size
    assert_includes paths, File.join(@temp_dir, "top.mp3")
    assert_includes paths, File.join(@temp_dir, "Artist/Album/nested.mp3")
  end

  test "returns absolute paths" do
    copy_fixture("Artist/song.mp3")

    LibraryScanner.new(@temp_dir).mp3_paths.each do |path|
      assert File.absolute_path?(path), "#{path} is not absolute"
    end
  end

  test "ignores files that are not MP3s" do
    copy_fixture("keep.mp3")
    File.write(File.join(@temp_dir, "cover.jpg"), "not audio")
    File.write(File.join(@temp_dir, "notes.txt"), "not audio")

    assert_equal [ File.join(@temp_dir, "keep.mp3") ], LibraryScanner.new(@temp_dir).mp3_paths
  end

  test "matches the extension case-insensitively" do
    copy_fixture("SHOUTING.MP3")

    assert_equal 1, LibraryScanner.new(@temp_dir).mp3_paths.size
  end

  test "finds files whose names contain spaces and brackets" do
    copy_fixture("Some Artist/A [Deluxe] Album/01 - Track.mp3")

    assert_equal 1, LibraryScanner.new(@temp_dir).mp3_paths.size
  end

  test "returns a sorted list so progress runs in a predictable order" do
    copy_fixture("c.mp3")
    copy_fixture("a.mp3")
    copy_fixture("b.mp3")

    assert_equal %w[ a.mp3 b.mp3 c.mp3 ],
      LibraryScanner.new(@temp_dir).mp3_paths.map { |path| File.basename(path) }
  end

  test "returns nothing for an empty library" do
    assert_empty LibraryScanner.new(@temp_dir).mp3_paths
  end

  test "returns nothing when the root does not exist" do
    assert_empty LibraryScanner.new(File.join(@temp_dir, "missing")).mp3_paths
  end
end
