class CreateSongs < ActiveRecord::Migration[8.1]
  def change
    create_table :songs do |t|
      t.string   :file_path, null: false
      t.string   :title
      t.string   :artist
      t.string   :album
      t.string   :genre
      t.integer  :year
      t.integer  :track_number
      t.integer  :disc_number
      t.integer  :duration                 # whole seconds
      t.integer  :bitrate                  # kbps
      t.bigint   :file_size
      t.datetime :file_modified_at
      t.string   :album_art_checksum       # MD5 of the APIC bytes; NULL means no art
      t.string   :album_art_content_type
      t.datetime :last_seen_at             # stamped by each sync pass; drives pruning

      t.timestamps
    end

    # The natural key: sync and upload both find_or_initialize_by(file_path:).
    add_index :songs, :file_path, unique: true

    # Every one of these is exposed as a sort column in the UI. Without an index
    # SQLite full-sorts the table on every page of results.
    add_index :songs, :title
    add_index :songs, :artist
    add_index :songs, :album
    add_index :songs, :genre
    add_index :songs, :year

    # Pruning after a sync is a range delete over this column.
    add_index :songs, :last_seen_at

    # The default listing order.
    add_index :songs, [ :artist, :album, :disc_number, :track_number ],
      name: "index_songs_on_album_ordering"
  end
end
