# One artist: every song sharing an album_artist.
#
# Grouped on album_artist rather than artist so that browsing matches the album
# shelf -- a compilation appears once under "Various Artists" rather than once
# per guest performer. See Album for why this is a PORO and not a table.
class Artist
  include ActiveModel::Model

  PER_PAGE = 48

  GROUPED_COLUMNS = <<~SQL.squish
    album_artist,
    COUNT(*)              AS songs_count,
    COUNT(DISTINCT album) AS albums_count,
    MIN(id)               AS cover_song_id
  SQL

  attr_accessor :name, :songs_count, :albums_count, :cover_song_id, :cover_checksum

  class << self
    def page(number, search: nil, per: PER_PAGE)
      relation = grouped(Song.contains(:album_artist, search)).page(number).per(per)

      Kaminari.paginate_array(build(relation.to_a), total_count: relation.total_count,
        limit: relation.limit_value, offset: relation.offset_value)
    end

    def find(param)
      name = LibraryKey.decode(param, 1).first
      artist = build(grouped(Song.where(album_artist: name)).to_a).first

      raise ActiveRecord::RecordNotFound, "No such artist" if artist.nil?

      artist
    end

    private
      def grouped(scope)
        scope.group(:album_artist).select(GROUPED_COLUMNS).order(:album_artist)
      end

      def build(rows)
        covers = Song.where(id: rows.map(&:cover_song_id)).pluck(:id, :album_art_checksum).to_h

        rows.map do |row|
          new(name: row.album_artist, songs_count: row.songs_count,
            albums_count: row.albums_count, cover_song_id: row.cover_song_id,
            cover_checksum: covers[row.cover_song_id])
        end
      end
  end

  def to_param = LibraryKey.encode(name)

  def display_name = name.presence || "Unknown artist"

  # Unpaginated: the widest real artist has a few dozen albums. Paginate it the
  # day that stops being true.
  def albums = Album.for_artist(name)
end
