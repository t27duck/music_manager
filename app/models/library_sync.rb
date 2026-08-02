# Imports every MP3 under the library root, updating songs that already exist
# and removing the ones whose files have been deleted from disk.
#
# Progress reporting -- the cache write, the broadcast and the throttle -- comes
# from ProgressReporting, which this shares with every other long-running
# operation.
class LibrarySync
  include ProgressReporting

  # Skipped files still have to be stamped as seen or #prune deletes them, but
  # doing that one row at a time is the very cost this feature removes. They are
  # collected and written in batches of this size instead.
  SKIP_STAMP_SLICE = 500

  class << self
    # Marks a sync as starting and queues it. Returns false if any operation is
    # already running, so a double-clicked button cannot start two -- and an
    # organize already in flight blocks a sync.
    #
    # The status is written here rather than in the job so the button disables
    # immediately, before a worker has picked the job up.
    def enqueue(force: false)
      return false if running?

      publish(Status.starting)
      LibrarySyncJob.perform_later(force: force)
      true
    end

    def call(force: false)
      new(force: force).call
    end
  end

  # force: re-reads every file's tags even when nothing about it looks changed.
  # The escape hatch for the one case the skip cannot see -- a file retagged
  # within the same second, to the same byte length.
  def initialize(root = Configuration.library_root, force: false)
    @root = root.to_s
    @force = force
    @errors = []
    @skipped_ids = []
    @skipped_count = 0
  end

  def call
    started_at = Time.current
    paths = LibraryScanner.new(@root).mp3_paths

    publish(current: 0, total: paths.size, filename: nil)
    import_all(paths)
    prune(started_at)

    publish(current: paths.size, total: paths.size, filename: nil, state: :completed)
  rescue StandardError => e
    # The bar must not spin forever if something unexpected goes wrong.
    @errors << e.message
    publish(current: 0, total: 0, filename: nil, state: :failed)
    raise
  end

  private
    attr_reader :errors

    def import_all(paths)
      total = paths.size
      @last_broadcast_at = nil

      paths.each_with_index do |path, index|
        current = index + 1
        import(path)

        if broadcast?(current, total)
          publish(current: current, total: total, filename: File.basename(path))
        end
      end

      # Must happen before #prune, or every skipped song looks unseen and is
      # deleted. Skipping the file is not the same as not visiting it.
      flush_skipped
    end

    # One unreadable file must not abort the whole run: log it, keep the record
    # alive so pruning does not delete it, and move on.
    #
    # The skip is checked here rather than in import_all so that every file
    # still counts towards progress -- the bar must not stall on a library that
    # is mostly unchanged.
    def import(path)
      return skip(path) if unchanged?(path)

      SongImporter.call(path)
    rescue Mp3File::Error, ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("LibrarySync could not import #{path}: #{e.message}")
      errors << "#{File.basename(path)}: #{e.message}"
      touch_existing(path)
    end

    # Whether the file can be left unread. Reading its tags means parsing ID3
    # and MD5-ing the embedded cover, which on a large library is nearly all of
    # a sync's cost and almost always produces exactly what is already stored.
    #
    # Compared on whole seconds, not the full timestamp: the column is
    # microsecond precision and Active Record floors File::Stat#mtime's
    # nanoseconds into it, so an exact match is unreachable on a filesystem that
    # reports them. file_size is the second signal -- rewriting ID3v2 tags
    # recalculates the padding and so nearly always changes the byte length.
    #
    # A file with no recorded timestamp never matches, which is the safe
    # direction: rows written before this existed re-import once, then skip.
    def unchanged?(path)
      return false if @force

      id, mtime, size = existing_index[path]
      return false if id.nil? || mtime.nil?

      stat = File.stat(path)
      mtime == stat.mtime.to_i && size == stat.size
    rescue SystemCallError
      false
    end

    # file_path => [id, mtime as whole seconds, size] for everything already
    # known about this library. Loaded once: a query per file would cost more
    # than the reads it saves. Roughly 4 MB for a 5,000 song library.
    def existing_index
      @existing_index ||= Song.in_library(@root)
        .pluck(:id, :file_path, :file_modified_at, :file_size)
        .to_h { |id, path, mtime, size| [ path, [ id, mtime&.to_i, size ] ] }
    end

    def skip(path)
      @skipped_count += 1
      @skipped_ids << existing_index.fetch(path).first
      flush_skipped if @skipped_ids.size >= SKIP_STAMP_SLICE
    end

    def flush_skipped
      return if @skipped_ids.empty?

      Song.where(id: @skipped_ids).update_all(last_seen_at: Time.current)
      @skipped_ids.clear
    end

    # Keeps a song whose file could not be re-read from looking stale to #prune.
    # The file is still on disk; only its tags were unreadable.
    def touch_existing(path)
      Song.where(file_path: path).update_all(last_seen_at: Time.current)
    end

    # Songs the scan did not reach have had their files deleted from disk.
    def prune(started_at)
      Song.in_library(@root).where(last_seen_at: ...started_at).delete_all
    end

    def publish(state: :running, **attributes)
      record_broadcast

      self.class.publish(
        Status.new(
          state: state,
          errors: errors.dup,
          finished_at: (Time.current if state != :running),
          skipped: @skipped_count,
          **attributes
        )
      )
    end
end
