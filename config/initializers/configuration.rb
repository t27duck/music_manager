# Application-wide settings that are not per-environment Rails config.
#
# The library root is memoized in a class-level ivar so tests can swap it for a
# temp directory with `Configuration.instance_variable_set(:@library_root, dir)`
# and restore it in teardown. Parallel tests fork processes, so each worker gets
# its own copy.
class Configuration
  class << self
    attr_writer :library_root

    # Absolute path to the directory holding the MP3 library.
    def library_root
      @library_root ||= ENV.fetch("LIBRARY_ROOT") { default_library_root }
    end

    def library_pathname
      Pathname.new(library_root)
    end

    # Path relative to the library root, for display. Falls back to the full
    # path when the file lives outside the library.
    def relative_path(path)
      Pathname.new(path.to_s).relative_path_from(library_pathname).to_s
    rescue ArgumentError
      path.to_s
    end

    private
      # Tests default to test/library so a test that forgets to stub the root
      # scans an empty directory instead of the user's real music.
      def default_library_root
        Rails.root.join(Rails.env.test? ? "test/library" : "library").to_s
      end
  end
end
