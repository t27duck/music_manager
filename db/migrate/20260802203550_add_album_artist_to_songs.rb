class AddAlbumArtistToSongs < ActiveRecord::Migration[8.1]
  def change
    add_column :songs, :album_artist, :string

    # Serves the album index's GROUP BY and the album page's track ordering.
    # index_songs_on_album_ordering stays: Song.ordered is still artist-first.
    add_index :songs, [ :album_artist, :album, :disc_number, :track_number ],
      name: "index_songs_on_album_grouping"

    # A floor, so /albums is never empty between this migration and the first
    # sync that actually reads TPE2. Grouping by the track artist is exactly
    # today's behaviour; LibrarySync::TAG_EPOCH replaces it on the next run.
    up_only { execute "UPDATE songs SET album_artist = artist" }
  end
end
