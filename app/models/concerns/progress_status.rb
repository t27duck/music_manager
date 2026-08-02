# The questions every long-running operation's progress answers.
#
# Included into each operation's own Status value object rather than replacing
# them with one shared shape: a sync reports how many files it skipped, an
# organize how many it moved, and folding those into a generic bag of data would
# turn every exact assertion about them into a string match.
#
# `state` is compared as a String throughout, because it arrives two ways: as a
# Symbol on the in-flight Data objects, and as a database column on SyncRun. One
# mixin has to serve both, so neither can assume the other's type.
module ProgressStatus
  def running? = state.to_s == "running"
  def completed? = state.to_s == "completed"
  def failed? = state.to_s == "failed"

  # Running is the only unfinished state, so this is derived rather than listed.
  def finished? = !running?

  def errors? = errors.present?

  # What the bar says about failures. Operations that have a better word for
  # what they were doing to the file override this, the way they override
  # #message -- the bar itself cannot know.
  def errors_message = "#{errors.size} #{"file".pluralize(errors.size)} could not be processed"

  # Whole percent, used for the width of the progress bar. An operation that has
  # not counted its work yet reads as 0%.
  def percent
    return 0 if total.to_i.zero?

    ((current.to_f / total) * 100).clamp(0, 100).round
  end

  def counter = "#{current}/#{total}"
end
