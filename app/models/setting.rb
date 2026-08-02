# An application preference that outlives a browser session.
#
# A generic key/value row rather than a column per preference: there is no User
# model and no authentication, so these are settings for the app itself, and a
# new one should not need a migration.
#
# The accessors are deliberately shaped like Hash and like `session`, which is
# what they replaced:
#
#   Setting[:path_template] = "<Artist>/<Album>/<Title>"
#   Setting[:path_template]  # => "<Artist>/<Album>/<Title>"
#
# Values are read straight from the table. It holds a handful of rows and the
# lookup is a unique-index hit, so caching would buy nothing and cost an
# invalidation path.
class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.[](name)
    find_by(key: name.to_s)&.value
  end

  def self.[]=(name, value)
    find_or_initialize_by(key: name.to_s).update!(value: value)
    value
  end
end
