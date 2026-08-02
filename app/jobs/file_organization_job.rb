class FileOrganizationJob < ApplicationJob
  queue_as :default

  # Ids rather than records: the selection can be the whole library, and this
  # has to survive a JSON round trip through the queue in production.
  def perform(song_ids:, template:)
    FileOrganization.call(song_ids: song_ids, template: template)
  end
end
