# One album: every song sharing an (album_artist, album) pair.
#
# Deliberately not a table. The file on disk is the source of truth -- the same
# reasoning that keeps Active Storage disabled -- so an albums table would need
# syncing and pruning on every tag edit, and would raise "which wins when the
# file changes underneath us?" for no query benefit at this size.
#
# Not a bare grouped query either: a grouped `select` on Song returns Song
# instances whose id is nil, and handing those to a view invites `song.title` on
# a phantom record. This keeps the phantom confined to .from_row.
class Album
  include ActiveModel::Model

  # Divides evenly by 2, 3, 4 and 6 -- the grid's column counts.
  PER_PAGE = 48

  SEARCH_COLUMNS = %w[ album_artist album ].freeze

  # MIN(id) picks a representative song for the cover. Its checksum is fetched
  # separately, keyed on these ids: SQLite's bare-column rule would pair them
  # correctly, but a reader cannot check that, and a wrong cover is silent.
  GROUPED_COLUMNS = <<~SQL.squish
    album_artist, album,
    COUNT(*)      AS songs_count,
    SUM(duration) AS total_duration,
    MIN(year)     AS first_year,
    MAX(year)     AS last_year,
    MIN(id)       AS cover_song_id
  SQL

  attr_accessor :artist, :name, :songs_count, :total_duration,
                :first_year, :last_year, :cover_song_id, :cover_checksum

  class << self
    def page(number, search: nil, per: PER_PAGE)
      relation = grouped(Song.contains(SEARCH_COLUMNS, search)).page(number).per(per)

      paginate(build(relation.to_a), relation)
    end

    # Every album by one artist. Unpaginated: the widest real artist has a few
    # dozen albums. Paginate it the day that stops being true.
    def for_artist(artist)
      build(grouped(Song.where(album_artist: artist)).to_a)
    end

    def find(param)
      artist, name = LibraryKey.decode(param, 2)
      album = build(grouped(scope_for(artist, name)).to_a).first

      raise ActiveRecord::RecordNotFound, "No such album" if album.nil?

      album
    end

    # Exposed so Artist can reuse the aggregate without duplicating the SQL.
    def grouped(scope)
      scope.group(:album_artist, :album).select(GROUPED_COLUMNS).order(:album_artist, :album)
    end

    private
      def scope_for(artist, name)
        Song.where(album_artist: artist, album: name)
      end

      def build(rows)
        covers = Song.where(id: rows.map(&:cover_song_id)).pluck(:id, :album_art_checksum).to_h

        rows.map { |row| from_row(row, covers[row.cover_song_id]) }
      end

      def from_row(row, cover_checksum)
        new(
          artist: row.album_artist, name: row.album,
          songs_count: row.songs_count, total_duration: row.total_duration,
          first_year: row.first_year, last_year: row.last_year,
          cover_song_id: row.cover_song_id, cover_checksum: cover_checksum
        )
      end

      # Kaminari cannot paginate an array and a relation at once, so the relation
      # does the slicing and this only re-wraps the built objects with the same
      # window. total_count on a GROUP BY relation is an Integer here, not the
      # Hash the usual warning is about.
      def paginate(albums, relation)
        Kaminari.paginate_array(albums, total_count: relation.total_count,
          limit: relation.limit_value, offset: relation.offset_value)
      end
  end

  def to_param = LibraryKey.encode(artist, name)

  # For linking through to the artist page without building a throwaway Artist.
  def artist_param = LibraryKey.encode(artist)

  def display_name = name.presence || "Unknown album"
  def display_artist = artist.presence || "Unknown artist"

  def songs
    Song.where(album_artist: artist, album: name)
        .order(:disc_number, :track_number, :title)
  end

  # "1996", "1996–1999", or nil when nothing is tagged.
  def years
    return nil if first_year.blank?
    return first_year.to_s if last_year.blank? || first_year == last_year

    "#{first_year}–#{last_year}"
  end
end
