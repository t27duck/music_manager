# Isolation for tests that touch files on disk.
#
# Every including test gets its own temp directory as the library root, so tests
# never see each other's files and never touch the real music library. The root
# is stubbed via the memoized class ivar, which is per-process and therefore
# safe under parallel testing.
module LibraryTestHelper
  extend ActiveSupport::Concern

  FIXTURE_MP3 = "song 1.mp3".freeze
  FIXTURE_COVER = "cover.jpg".freeze

  included do
    setup do
      @temp_dir = Dir.mktmpdir("music_manager_#{Process.pid}_#{Thread.current.object_id}")
      @original_library_root = Configuration.library_root
      Configuration.instance_variable_set(:@library_root, @temp_dir)
    end

    teardown do
      Configuration.instance_variable_set(:@library_root, @original_library_root)
      FileUtils.remove_entry(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    end
  end

  # Absolute path to a fixture file shipped in test/fixtures/files.
  def fixture_file(name)
    Rails.root.join("test/fixtures/files", name).to_s
  end

  # Copies a fixture MP3 to dest_subpath inside the temp library and returns the
  # absolute path. Parent directories are created as needed.
  def copy_fixture(dest_subpath, fixture_name: FIXTURE_MP3)
    dest = File.join(@temp_dir, dest_subpath)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(fixture_file(fixture_name), dest)
    dest
  end

  # Creates a Song backed by a real MP3 inside the temp library.
  #
  # Tags are not written back to the file (skip_tag_write), so the file keeps the
  # fixture's own tags; pass through Song#update in the test if you want the
  # write-through callback to run.
  def create_test_song(dest_subpath, fixture_name: FIXTURE_MP3, **attributes)
    path = copy_fixture(dest_subpath, fixture_name: fixture_name)

    song = Song.new(
      file_path: path,
      title: "Test Song",
      artist: "Test Artist",
      file_size: File.size(path),
      duration: 180,
      **attributes
    )
    song.skip_tag_write = true
    song.save!
    song
  end

  # Scopes a query to the current test's temp directory. Use this instead of
  # Song.all when asserting on jobs that operate over the whole library.
  # Note the explicit ESCAPE: SQLite ignores the backslashes sanitize_sql_like
  # inserts unless told what the escape character is, and temp directory names
  # are full of underscores -- which LIKE would otherwise treat as wildcards.
  def songs_in_temp_dir
    Song.where("file_path LIKE ? ESCAPE ?", "#{Song.sanitize_sql_like(@temp_dir)}/%", "\\")
  end

  # Reads tags straight back off disk, bypassing the database.
  def tags_on_disk(path)
    Mp3File.new(path).attributes
  end
end
