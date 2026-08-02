class BulkEditJob < ApplicationJob
  queue_as :default

  # Ids and primitives only; the album art is a path to bytes spooled at enqueue
  # time, because the image itself cannot ride in job arguments.
  def perform(song_ids:, attributes: {}, album_art_path: nil, remove_album_art: false)
    BulkEdit.call(song_ids: song_ids, attributes: attributes,
      album_art_path: album_art_path, remove_album_art: remove_album_art)
  end
end
