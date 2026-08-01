# Imports every MP3 under the library root, updating songs that already exist
# and removing the ones whose files have been deleted from disk.
#
# Progress is published two ways at once: written to the cache (so a page load
# mid-sync renders the current state) and broadcast over Turbo Streams (so open
# pages update live). Both go through #publish, so they can never disagree.
class LibrarySync
  CACHE_KEY = "library_sync:status".freeze
  STREAM = "library_sync".freeze
  STATUS_TTL = 1.hour

  # Broadcasting on every file would flood the cable on a large library, so
  # updates are throttled to at most one per BROADCAST_EVERY files and never
  # more often than BROADCAST_INTERVAL apart. The first and last file always
  # broadcast, so the bar starts and finishes cleanly.
  BROADCAST_EVERY = 10
  BROADCAST_INTERVAL = 0.1

  class << self
    def status
      Rails.cache.read(CACHE_KEY)
    end

    def running?
      status&.running? || false
    end

    # Marks a sync as starting and queues it. Returns false if one is already
    # running, so a double-clicked button cannot start two.
    #
    # The status is written here rather than in the job so the button disables
    # immediately, before a worker has picked the job up.
    def enqueue
      return false if running?

      publish(Status.starting)
      LibrarySyncJob.perform_later
      true
    end

    def call
      new.call
    end

    # Writes the status to the cache and broadcasts it to every open page.
    def publish(status)
      Rails.cache.write(CACHE_KEY, status, expires_in: STATUS_TTL)
      Turbo::StreamsChannel.broadcast_render_to(STREAM,
        partial: "syncs/update", locals: { status: status })
      status
    end
  end

  def initialize(root = Configuration.library_root)
    @root = root.to_s
    @errors = []
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
    end

    # One unreadable file must not abort the whole run: log it, keep the record
    # alive so pruning does not delete it, and move on.
    def import(path)
      SongImporter.call(path)
    rescue Mp3File::Error, ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("LibrarySync could not import #{path}: #{e.message}")
      errors << "#{File.basename(path)}: #{e.message}"
      touch_existing(path)
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

    def broadcast?(current, total)
      return true if current == 1 || current == total
      return false unless (current % BROADCAST_EVERY).zero?

      elapsed = @last_broadcast_at.nil? || (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_broadcast_at) >= BROADCAST_INTERVAL
      elapsed
    end

    def publish(state: :running, **attributes)
      @last_broadcast_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      self.class.publish(
        Status.new(
          state: state,
          errors: errors.dup,
          finished_at: (Time.current if state != :running),
          **attributes
        )
      )
    end
end
