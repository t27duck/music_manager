# Re-files a selection of songs in the background, reporting progress.
#
# FileOrganizer does the moving and knows nothing about jobs or broadcasts; this
# wraps it the way LibrarySync wraps LibraryScanner. It exists because a large
# selection is far too slow to move inside a request -- moving is a filesystem
# operation per file, and the selection can be the whole library.
class FileOrganization
  include ProgressReporting

  # Everything here is a primitive on purpose. FileOrganizer::Result holds Move
  # objects which hold live Song records, and Marshalling those into the cache
  # would both bloat it and hand a stale record back on read.
  Status = Data.define(:state, :current, :total, :filename, :errors, :finished_at,
                       :moved, :unchanged, :summary) do
    include ProgressStatus

    def self.starting(total: 0)
      new(state: :running, current: 0, total: total, filename: nil, errors: [],
        finished_at: nil, moved: 0, unchanged: 0, summary: nil)
    end

    def errors_message = "#{errors.size} #{"file".pluralize(errors.size)} could not be moved"

    def message
      if failed? then "Organizing failed"
      elsif completed? then summary.presence || "Files organized"
      else "Organizing files…"
      end
    end
  end

  class << self
    # Returns false if any operation is already running -- a sync prunes rows
    # whose files this would be moving.
    def enqueue(song_ids:, template:)
      return false if running?

      publish(Status.starting(total: song_ids.size))
      FileOrganizationJob.perform_later(song_ids: song_ids, template: template)
      true
    end

    def call(song_ids:, template:) = new(song_ids: song_ids, template: template).call
  end

  def initialize(song_ids:, template:)
    @song_ids = Array(song_ids)
    @template = template.to_s
  end

  def call
    songs = Song.where(id: @song_ids).ordered.to_a
    organizer = FileOrganizer.new(@template)
    total = songs.size

    publish(current: 0, total: total)

    result = organizer.apply!(songs) do |current, count, move|
      record_move(move)
      publish(current: current, total: count, filename: display_name(move)) if broadcast?(current, count)
    end

    # Remembered only once the moves have actually been made: a template that
    # failed to save is a better outcome than one remembered for moves that
    # never happened.
    Setting[:path_template] = @template

    publish(current: total, total: total, state: :completed, summary: result.summary)
  rescue StandardError => e
    # The bar must not spin forever if something unexpected goes wrong.
    errors << e.message
    publish(current: 0, total: 0, state: :failed)
    raise
  end

  private
    def errors = @errors ||= []

    def record_move(move)
      if move.failed?
        errors << "#{move.song.filename}: #{move.error}"
      elsif move.unchanged?
        @unchanged = unchanged + 1
      else
        @moved = moved + 1
      end
    end

    def moved = @moved ||= 0
    def unchanged = @unchanged ||= 0

    # A basename, never the Move itself -- the status must stay Marshal-safe.
    def display_name(move)
      File.basename(move.to || move.from)
    end

    def publish(state: :running, **attributes)
      record_broadcast

      self.class.publish(
        Status.new(
          state: state,
          filename: nil,
          errors: errors.dup,
          finished_at: (Time.current if state != :running),
          moved: moved,
          unchanged: unchanged,
          summary: nil,
          **attributes
        )
      )
    end
end
