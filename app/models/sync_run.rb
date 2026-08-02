# The durable record of one library sync.
#
# Distinct from LibrarySync::Status, which is the *live* progress: that is
# transient, rewritten on every broadcast, and belongs in the cache. This is
# written exactly twice -- once as a run begins and once as it ends -- so it
# never sits in the hot path, and it answers a different question: what has
# happened to this library over time.
#
# It includes ProgressStatus so a stored run renders through the same partial
# and the same colour helpers as a live one. That is why `state` is compared as
# a string: here it is a column, there it is a Symbol.
class SyncRun < ApplicationRecord
  include ProgressStatus

  STATES = %w[ running completed failed ].freeze

  # How many runs to keep. A hundred is far more history than a single-user
  # library needs and still small enough that the table never needs pruning
  # attention of its own.
  KEEP = 100

  # A catastrophic run could otherwise write a megabyte of near-identical
  # messages into a row nobody queries.
  FAILURE_LIMIT = 50

  # Named `failures`, not `errors`: `errors` is ActiveModel::Errors on any
  # Active Record model, and shadowing it is a footgun.
  # A run with no failures stores NULL, which reads back as []: the serialized
  # type maps an empty array to NULL because it equals the coder's own default.
  serialize :failures, type: Array, coder: JSON

  validates :state, inclusion: { in: STATES }

  scope :recent, -> { order(created_at: :desc) }

  paginates_per 25

  # Opens a run, trimming the history first so the table is bounded *before*
  # the row that would exceed the cap exists -- and so a run that dies without
  # finishing cannot leave the cap unenforced forever.
  def self.start!(forced: false)
    where.not(id: recent.limit(KEEP - 1).select(:id)).delete_all

    create!(state: "running", forced: forced)
  end

  # Closes a run from the terminal progress status.
  def finish!(status)
    update!(
      state: status.state.to_s,
      total: status.total,
      skipped: status.skipped,
      failures: status.errors.first(FAILURE_LIMIT),
      finished_at: status.finished_at || Time.current
    )
  end

  # ProgressStatus asks about `errors`, which on an Active Record model is the
  # validation object and must stay that way. Only the two methods that read it
  # are overridden, so validations are untouched.
  def errors? = failures.any?
  def errors_message = "#{failures.size} #{"file".pluralize(failures.size)} could not be imported"

  # Satisfies ProgressStatus#percent and #counter. A run has worked through
  # everything it found by the time it is finished.
  def current = total

  # A run only stays "running" if the process died mid-sync, so after the live
  # status would have expired there is nothing left that could finish it.
  def stale?
    running? && created_at < ProgressReporting::STATUS_TTL.ago
  end

  def duration
    return nil unless finished_at

    (finished_at - created_at).round
  end
end
