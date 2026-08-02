# Applies one set of changes to many songs.
#
# Deliberately not wrapped in a single transaction: each song is a separate file
# on disk, and one unwritable file must not undo the songs that were written
# successfully. Failures are collected and reported instead, so the user is told
# exactly what did and did not change.
class Song::BulkUpdate
  # Only these are offered in bulk. Title is absent on purpose -- giving fifty
  # songs the same title is never what anyone means.
  # Album artist is here because bulk editing is how a mis-tagged compilation
  # gets fixed: select the album's songs and give them all one album artist.
  FIELDS = %w[ artist album_artist album genre year disc_number ].freeze

  Result = Data.define(:updated, :failures) do
    def updated_count = updated.size
    def failure_count = failures.size
    def any_failures? = failures.any?
    def nothing_to_do? = updated.empty? && failures.empty?

    def summary
      parts = [ "#{updated_count} #{'song'.pluralize(updated_count)} updated" ]
      parts << "#{failure_count} failed" if any_failures?
      parts.join(", ") + "."
    end
  end

  Failure = Data.define(:song, :message)

  attr_reader :songs, :attributes, :album_art, :remove_album_art

  # attributes: only non-blank values are applied, so a field left empty in the
  # form leaves that field alone on every song rather than clearing it.
  def initialize(songs, attributes: {}, album_art: nil, remove_album_art: false)
    @songs = songs
    @attributes = attributes.to_h.compact_blank.slice(*FIELDS)
    @album_art = album_art
    @remove_album_art = remove_album_art
  end

  # Yields (current, total, song, message) after each song, for a caller that
  # wants to report progress. Optional, so the synchronous callers and their
  # tests are unaffected; `message` is nil when the song was updated.
  def call
    updated = []
    failures = []
    total = songs.size

    songs.each_with_index do |song, index|
      message = apply_to(song)

      if message
        failures << Failure.new(song: song, message: message)
      else
        updated << song
      end

      yield(index + 1, total, song, message) if block_given?
    end

    Result.new(updated: updated, failures: failures)
  end

  # Whether there is anything to do at all, so the caller can refuse an empty
  # submission rather than reporting "0 songs updated".
  def changes?
    attributes.any? || album_art.present? || remove_album_art
  end

  private
    # Returns nil when the song was updated, or a message explaining why not.
    # #update rather than #update! so the model's own error -- "Could not write
    # tags to X" -- reaches the user instead of a generic "Failed to save".
    def apply_to(song)
      if attributes.any? && !song.update(attributes)
        return song.errors.full_messages.to_sentence
      end

      if album_art.present?
        song.update_album_art!(album_art)
      elsif remove_album_art
        song.remove_album_art!
      end

      nil
    rescue Song::InvalidAlbumArt, Mp3File::Error, ActiveRecord::ActiveRecordError => e
      e.message
    end
end
