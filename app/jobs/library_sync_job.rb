class LibrarySyncJob < ApplicationJob
  queue_as :default

  def perform(force: false)
    LibrarySync.call(force: force)
  end
end
