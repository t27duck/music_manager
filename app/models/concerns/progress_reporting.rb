# Publishing the progress of one long-running operation.
#
# Progress is published two ways at once: written to the cache (so a page load
# mid-run renders the current state) and broadcast over Turbo Streams (so open
# pages update live). Both go through .publish, so they can never disagree.
#
# There is deliberately **one** region, one cache key and one stream for the
# whole application, and operations are mutually exclusive rather than stacked.
# A sync prunes song rows while an organize moves the files underneath them;
# showing two bars would advertise a concurrency the app must not have. So
# .busy? is asked across all operations, and every enqueue checks it.
module ProgressReporting
  extend ActiveSupport::Concern

  STREAM = "progress".freeze

  # Versioned: a Status is a Data object and the cache Marshals it, so a status
  # written before a member was added cannot be loaded into the new shape.
  # Bumping the key retires those entries instead of raising on them.
  CACHE_KEY = "progress:status:v1".freeze
  STATUS_TTL = 1.hour

  # Broadcasting on every item would flood the cable on a large library, so
  # updates are throttled to at most one per BROADCAST_EVERY items and never
  # more often than BROADCAST_INTERVAL apart. The first and last item always
  # broadcast, so the bar starts and finishes cleanly.
  BROADCAST_EVERY = 10
  BROADCAST_INTERVAL = 0.1

  # Whatever published most recently, whichever operation that was.
  def self.current
    Rails.cache.read(CACHE_KEY)
  end

  def self.busy?
    current&.running? || false
  end

  class_methods do
    # The current progress, but only if it belongs to this operation. One cache
    # key holds either shape, so the caller has to be told "not yours" rather
    # than handed a sync's status when it asked about an organize.
    def status
      current = ProgressReporting.current
      current if current.is_a?(self::Status)
    end

    # Deliberately not scoped to this operation: nothing may start while
    # anything else is running.
    def running? = ProgressReporting.busy?

    def publish(status)
      Rails.cache.write(CACHE_KEY, status, expires_in: STATUS_TTL)
      Turbo::StreamsChannel.broadcast_render_to(STREAM,
        partial: "progress/update", locals: { status: status })
      status
    end
  end

  private
    def broadcast?(current, total)
      return true if current == 1 || current == total
      return false unless (current % BROADCAST_EVERY).zero?

      @last_broadcast_at.nil? ||
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_broadcast_at) >= BROADCAST_INTERVAL
    end

    def record_broadcast
      @last_broadcast_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
end
