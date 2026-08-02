# Moves song files into the layout described by a PathTemplate.
#
# #preview and #apply! answer the same question, so the user is shown exactly
# what will happen: #apply! computes the same moves and then performs them.
class FileOrganizer
  Move = Data.define(:song, :from, :to, :error) do
    def unchanged? = error.nil? && from == to
    def failed? = error.present?
    def moving? = error.nil? && from != to
  end

  Result = Data.define(:moved, :unchanged, :failures) do
    def moved_count = moved.size
    def failure_count = failures.size
    def any_failures? = failures.any?

    def summary
      parts = [ "#{moved_count} #{'file'.pluralize(moved_count)} moved" ]
      parts << "#{unchanged.size} already in place" if unchanged.any?
      parts << "#{failure_count} failed" if any_failures?
      parts.join(", ") + "."
    end
  end

  attr_reader :template, :root

  def initialize(template, root: Configuration.library_root)
    @template = template.is_a?(PathTemplate) ? template : PathTemplate.new(template)
    @root = File.expand_path(root.to_s)
  end

  # What would happen, in order. Collisions are resolved here rather than at
  # apply time so the preview shows the suffixed name the user will actually get.
  def preview(songs)
    claimed = Set.new

    songs.map do |song|
      move_for(song, claimed).tap { |move| claimed << move.to if move.to }
    end
  end

  # Yields (current, total, move) after each file, for a caller that wants to
  # report progress. Optional, so the synchronous callers and their tests are
  # unaffected; it yields *after* the move so the count is of completed work.
  def apply!(songs)
    moved = []
    unchanged = []
    failures = []
    moves = preview(songs)

    moves.each_with_index do |move, index|
      if move.failed?
        failures << move
      elsif move.unchanged?
        unchanged << move
      elsif (error = perform(move))
        move = Move.new(song: move.song, from: move.from, to: move.to, error: error)
        failures << move
      else
        moved << move
      end

      yield(index + 1, moves.size, move) if block_given?
    end

    Result.new(moved: moved, unchanged: unchanged, failures: failures)
  end

  private
    def move_for(song, claimed)
      relative = template.render(song)
      target = File.expand_path(File.join(root, relative))

      unless inside_root?(target)
        return Move.new(song: song, from: song.file_path, to: nil,
          error: "The template would place this file outside the library.")
      end

      Move.new(song: song, from: song.file_path, to: deduplicate(target, claimed, song), error: nil)
    rescue PathTemplate::Error => e
      Move.new(song: song, from: song.file_path, to: nil, error: e.message)
    end

    # Belt and braces: PathTemplate already rejects ".." and absolute templates,
    # but a token *value* could still contain something surprising.
    def inside_root?(path)
      path.start_with?(root + File::SEPARATOR)
    end

    # Two songs can render to the same name, and an unrelated file may already
    # be sitting there. Suffix until the name is free.
    def deduplicate(target, claimed, song)
      return target if target == song.file_path

      extension = File.extname(target)
      base = target.delete_suffix(extension)
      candidate = target
      counter = 1

      while claimed.include?(candidate) || File.exist?(candidate)
        counter += 1
        candidate = "#{base} (#{counter})#{extension}"
      end

      candidate
    end

    # Returns nil on success or a message on failure. The record is updated
    # inside a transaction that wraps the move, so a move that fails leaves the
    # database untouched rather than pointing at a file that never arrived.
    def perform(move)
      move.song.transaction do
        move.song.update!(file_path: move.to)
        FileUtils.mkdir_p(File.dirname(move.to))
        FileUtils.mv(move.from, move.to)
      end

      prune_empty_directories(File.dirname(move.from))
      nil
    rescue SystemCallError, IOError, ActiveRecord::ActiveRecordError => e
      # The transaction rolled back, but the failed assignment is still sitting
      # on the in-memory record. Discard it so the caller is not left holding a
      # song that claims to live somewhere it does not.
      move.song.reload
      e.message
    end

    # Walks up from a vacated directory, removing whatever is now empty, and
    # stops at the library root.
    def prune_empty_directories(directory)
      directory = File.expand_path(directory)

      while inside_root?(directory) && Dir.exist?(directory) && Dir.empty?(directory)
        Dir.rmdir(directory)
        directory = File.dirname(directory)
      end
    rescue SystemCallError
      # Losing a race to remove a directory is not worth failing the move over.
      nil
    end
end
