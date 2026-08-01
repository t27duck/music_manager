class LibrarySyncJob < ApplicationJob
  queue_as :default

  def perform
    LibrarySync.call
  end
end
