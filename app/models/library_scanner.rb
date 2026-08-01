# Finds the MP3 files under a library root.
#
# Kept separate from LibrarySync so the traversal can be tested on its own, and
# so the sync's progress total is known before any file is imported.
class LibraryScanner
  EXTENSION = ".mp3".freeze

  attr_reader :root

  def initialize(root = Configuration.library_root)
    @root = root.to_s
  end

  # Absolute paths of every MP3 under the root, sorted so that progress runs in
  # a predictable order.
  #
  # The tree is globbed in full and filtered by extension rather than globbed
  # as "**/*.mp3": Dir.glob ignores File::FNM_CASEFOLD for this pattern, so a
  # file named .MP3 would be missed. Dir.glob skips dotfiles and dot-directories
  # by default, which is what we want.
  def mp3_paths
    return [] unless Dir.exist?(root)

    Dir.glob("**/*", base: root)
       .select { |relative| mp3?(File.join(root, relative)) }
       .sort
       .map { |relative| File.join(root, relative) }
  end

  private
    def mp3?(path)
      File.extname(path).downcase == EXTENSION && File.file?(path)
    end
end
