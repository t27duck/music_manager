# Applies one set of changes to many songs in the background, reporting progress.
#
# Song::BulkUpdate does the work and knows nothing about jobs or broadcasts;
# this wraps it the way FileOrganization wraps FileOrganizer. It exists because
# every changed song has its ID3 tags rewritten, which is a whole-file rewrite:
# measured at ~10ms per file on a real library, so the full 4,892 songs take the
# better part of a minute and cannot be done inside a request.
class BulkEdit
  include ProgressReporting

  # Uploaded album art waits here between the request that received it and the
  # job that applies it. Under tmp/, which is gitignored.
  SPOOL_DIRECTORY = Rails.root.join("tmp/bulk_album_art").to_s.freeze

  # Primitives only -- see FileOrganization::Status for why.
  Status = Data.define(:state, :current, :total, :filename, :errors, :finished_at,
                       :updated, :summary) do
    include ProgressStatus

    def self.starting(total: 0)
      new(state: :running, current: 0, total: total, filename: nil, errors: [],
        finished_at: nil, updated: 0, summary: nil)
    end

    def errors_message = "#{errors.size} #{"song".pluralize(errors.size)} could not be updated"

    def message
      if failed? then "Bulk edit failed"
      elsif completed? then summary.presence || "Songs updated"
      else "Updating songs…"
      end
    end
  end

  class << self
    def enqueue(song_ids:, attributes: {}, album_art_path: nil, remove_album_art: false)
      return false if running?

      publish(Status.starting(total: song_ids.size))
      BulkEditJob.perform_later(song_ids: song_ids, attributes: attributes,
        album_art_path: album_art_path, remove_album_art: remove_album_art)
      true
    end

    def call(...) = new(...).call

    # Album art arrives as uploaded bytes, which cannot ride in job arguments.
    # It is spooled to disk at enqueue time and the path is passed instead.
    #
    # Deliberately not Tempfile: Tempfile unlinks the file from a GC finalizer,
    # so handing out its path and dropping the object means the art can vanish
    # before the job opens it -- which is exactly what happened. This file's
    # lifetime is owned by the job, which deletes it in an ensure.
    def spool_album_art(data)
      return nil if data.blank?

      FileUtils.mkdir_p(SPOOL_DIRECTORY)
      path = File.join(SPOOL_DIRECTORY, "#{SecureRandom.hex(16)}.bin")
      File.binwrite(path, data)
      path
    end
  end

  def initialize(song_ids:, attributes: {}, album_art_path: nil, remove_album_art: false)
    @song_ids = Array(song_ids)
    @attributes = attributes || {}
    @album_art_path = album_art_path
    @remove_album_art = remove_album_art
  end

  def call
    songs = Song.where(id: @song_ids).ordered.to_a
    total = songs.size

    publish(current: 0, total: total)

    result = bulk_update(songs).call do |current, count, song, message|
      errors << "#{song.title}: #{message}" if message
      @updated = updated + 1 unless message
      publish(current: current, total: count, filename: song.title) if broadcast?(current, count)
    end

    publish(current: total, total: total, state: :completed, summary: result.summary)
  rescue StandardError => e
    errors << e.message
    publish(current: 0, total: 0, state: :failed)
    raise
  ensure
    # The spooled art is this run's alone, however the run ended.
    FileUtils.rm_f(@album_art_path) if @album_art_path
  end

  private
    def errors = @errors ||= []
    def updated = @updated ||= 0

    def bulk_update(songs)
      Song::BulkUpdate.new(songs,
        attributes: @attributes,
        album_art: album_art,
        remove_album_art: @remove_album_art)
    end

    def album_art
      return nil if @album_art_path.blank?

      @album_art ||= File.binread(@album_art_path)
    end

    def publish(state: :running, **attributes)
      record_broadcast

      self.class.publish(
        Status.new(
          state: state,
          filename: nil,
          errors: errors.dup,
          finished_at: (Time.current if state != :running),
          updated: updated,
          summary: nil,
          **attributes
        )
      )
    end
end
