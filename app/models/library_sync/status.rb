class LibrarySync
  # A snapshot of an in-flight or finished sync.
  #
  # Deliberately not an Active Record model: progress is transient, and keeping
  # it in the cache means no table, no migration, and no rows to clean up. It
  # is written on every broadcast and read on page load, so a browser refresh
  # mid-sync still shows the bar.
  Status = Data.define(:state, :current, :total, :filename, :errors, :finished_at, :skipped) do
    def self.starting
      new(state: :running, current: 0, total: 0, filename: nil, errors: [], finished_at: nil,
        skipped: 0)
    end

    def running? = state == :running
    def completed? = state == :completed
    def failed? = state == :failed
    def finished? = !running?

    def errors? = errors.any?

    # Files whose tags were left unread because neither their timestamp nor
    # their size had changed since the last sync.
    def skipped? = skipped.to_i.positive?

    # Whole percent, used for the width of the progress bar. A sync that has not
    # counted its files yet reads as 0%.
    def percent
      return 0 if total.to_i.zero?

      ((current.to_f / total) * 100).clamp(0, 100).round
    end

    def to_progress = "#{current}/#{total}"
  end
end
