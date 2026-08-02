class LibrarySync
  # A snapshot of an in-flight or finished sync.
  #
  # Deliberately not an Active Record model: *progress* is transient. It is
  # rewritten on every broadcast and read on page load, so a browser refresh
  # mid-sync still shows the bar, and the cache means no rows to clean up.
  #
  # The durable record of a run is SyncRun, which is a different question --
  # what has happened to this library over time -- and is written once at the
  # start of a run and once at the end, never in the hot path.
  Status = Data.define(:state, :current, :total, :filename, :errors, :finished_at, :skipped) do
    include ProgressStatus

    def self.starting
      new(state: :running, current: 0, total: 0, filename: nil, errors: [], finished_at: nil,
        skipped: 0)
    end

    # Files whose tags were left unread because neither their timestamp nor
    # their size had changed since the last sync.
    def skipped? = skipped.to_i.positive?

    def errors_message = "#{errors.size} #{"file".pluralize(errors.size)} could not be imported"

    # The line the progress bar shows. It lives here rather than in a helper
    # because only a sync knows that "unchanged" is a thing worth reporting --
    # the bar itself is shared with operations that have no such notion.
    def message
      if failed? then "Sync failed"
      elsif completed? && skipped? then "Sync complete — #{skipped} unchanged"
      elsif completed? then "Sync complete"
      elsif total.zero? then "Scanning library…"
      else "Syncing library…"
      end
    end
  end
end
