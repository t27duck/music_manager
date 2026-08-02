class Song < ApplicationRecord
  # Attributes mirrored into the file's ID3 tags whenever they change.
  TAG_ATTRIBUTES = Mp3File::TAG_ATTRIBUTES

  # Metadata fields the user can edit, in display order.
  EDITABLE_FIELDS = %w[ title artist album genre year disc_number track_number ].freeze

  # Fields the "missing metadata" filter can look for.
  MISSING_METADATA_FIELDS = %w[ artist album genre year ].freeze

  # The scopes the search UI can drive. One list, so the Ransack allow-list, the
  # permitted params and the "are any filters active?" helpers cannot drift.
  FILTER_SCOPES = %w[
    text_contains title_contains artist_contains album_contains genre_contains
    file_path_contains missing_metadata
  ].freeze

  # Columns the global search box looks through, in one OR'd LIKE.
  TEXT_SEARCH_COLUMNS = %w[ title artist album genre ].freeze

  # SQLite ignores the backslashes sanitize_sql_like inserts unless the query
  # names the escape character, so every LIKE we build has to pass it through.
  LIKE_ESCAPE = "\\".freeze

  # Album art is embedded in the file, so an oversized image bloats every copy
  # of that song forever. These are generous for cover art.
  ALBUM_ART_CONTENT_TYPES = %w[ image/jpeg image/png image/gif ].freeze
  MAX_ALBUM_ART_BYTES = 5.megabytes

  # Raised when uploaded artwork is not something we are willing to embed.
  class InvalidAlbumArt < StandardError; end

  # Set by SongImporter, which is reading tags *from* the file and must not
  # immediately write them back. Applies to the next save only; it is cleared
  # afterwards so a record cannot silently stop writing tags for the rest of
  # its life.
  attr_accessor :skip_tag_write

  validates :file_path, presence: true, uniqueness: true

  # Store blank metadata as NULL so "missing metadata" filters are a plain IS NULL.
  normalizes :title, :artist, :album, :genre, with: ->(value) { value&.strip.presence }

  # Tags are written *before* the record is saved, so that a file we cannot
  # write aborts the save and leaves the database untouched. Rails only honours
  # `throw :abort` in before callbacks, and this ordering is the one that
  # matters: the database must never claim metadata the file does not have.
  before_save :write_tags_to_file, if: :tags_need_writing?
  after_save { self.skip_tag_write = false }

  paginates_per 50

  scope :ordered, -> { order(:artist, :album, :disc_number, :track_number, :title) }

  # Songs whose file lives under the given library root. The explicit ESCAPE is
  # required: sanitize_sql_like inserts backslashes, but SQLite ignores them
  # unless told what the escape character is, and a path full of underscores
  # would otherwise match far too much.
  scope :in_library, ->(root = Configuration.library_root) {
    where("file_path LIKE ? ESCAPE ?", "#{sanitize_sql_like(root)}/%", "\\")
  }

  # Every text filter goes through here rather than through Ransack's built-in
  # `cont`, which emits a bare LIKE: under SQLite that makes every underscore
  # the user types a single-character wildcard. Ransack cannot be made to emit
  # ESCAPE -- it calls the Arel predicate with exactly one argument, so the
  # escape character can never reach Arel::Nodes::Matches -- so the filters are
  # scopes instead.
  #
  # Columns come from the frozen constants in this class, never from params.
  def self.contains(columns, value)
    return all if value.blank?

    sql = Array(columns).map { |column| "#{column} LIKE :pattern ESCAPE :escape" }.join(" OR ")

    where(sql, pattern: "%#{sanitize_sql_like(value.to_s)}%", escape: LIKE_ESCAPE)
  end

  scope :text_contains, ->(value) { contains(TEXT_SEARCH_COLUMNS, value) }
  scope :title_contains, ->(value) { contains(:title, value) }
  scope :artist_contains, ->(value) { contains(:artist, value) }
  scope :album_contains, ->(value) { contains(:album, value) }
  scope :genre_contains, ->(value) { contains(:genre, value) }
  scope :file_path_contains, ->(value) { contains(:file_path, value) }

  # Songs missing a given piece of metadata. Blanks are normalized to NULL on
  # write, but older rows are matched defensively too.
  scope :missing_metadata, ->(field) {
    field = field.to_s
    next all unless MISSING_METADATA_FIELDS.include?(field)

    columns_hash[field].type == :string ? where(field => [ nil, "" ]) : where(field => nil)
  }

  # Ransack allow-lists. file_path is deliberately absent from the searchable
  # list -- it is searched through the escaped scope above -- but is sortable.
  def self.ransackable_attributes(_auth_object = nil)
    %w[ title artist album genre year track_number disc_number duration file_size created_at updated_at ]
  end

  def self.ransortable_attributes(_auth_object = nil)
    ransackable_attributes + %w[ file_path ]
  end

  def self.ransackable_scopes(_auth_object = nil)
    FILTER_SCOPES
  end

  # Ransack coerces a scope's argument through its TRUE_VALUES/FALSE_VALUES list
  # unless the scope opts out, so searching for "t" would call the scope with
  # `true` -- and, since Rails scopes report an arity of -1, with no argument at
  # all, raising ArgumentError. "0" fared worse: it was treated as false and the
  # filter silently did nothing. Every one of these takes a user-typed string.
  def self.ransackable_scopes_skip_sanitize_args
    FILTER_SCOPES
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def filename
    File.basename(file_path.to_s)
  end

  def relative_path
    Configuration.relative_path(file_path)
  end

  def album_art?
    album_art_checksum.present?
  end

  # The embedded artwork's bytes, read straight from the file.
  def album_art
    Mp3File.new(file_path).album_art
  end

  # Embeds new artwork and records what it is, so the list can link to it and
  # the browser can cache it by checksum.
  def update_album_art!(data)
    data = validated_album_art(data)

    Mp3File.new(file_path).album_art = data
    update!(
      album_art_checksum: Digest::MD5.hexdigest(data),
      album_art_content_type: Mp3File.image_content_type(data)
    )
  end

  def remove_album_art!
    Mp3File.new(file_path).remove_album_art
    update!(album_art_checksum: nil, album_art_content_type: nil)
  end

  # Removes the song and its file. The file is deleted inside the transaction so
  # that a failure to delete it rolls the record back, rather than leaving a row
  # pointing at a file that is still there.
  #
  # Deliberately not a destroy callback: LibrarySync#prune deletes rows whose
  # files are already gone, and must never touch the filesystem.
  def destroy_with_file!
    transaction do
      destroy!
      File.delete(file_path) if File.exist?(file_path)
    end
  end

  private
    # The type is taken from the file's magic bytes, never from the upload's
    # declared content type or its extension -- both are trivially wrong. (The
    # cover.jpg test fixture is really a PNG, which is the case in point.)
    def validated_album_art(data)
      data = data.to_s.b

      raise InvalidAlbumArt, "The image is empty." if data.empty?

      if data.bytesize > MAX_ALBUM_ART_BYTES
        raise InvalidAlbumArt,
          "Album art must be #{number_to_human_size(MAX_ALBUM_ART_BYTES)} or smaller."
      end

      unless Mp3File.image_content_type(data).in?(ALBUM_ART_CONTENT_TYPES)
        raise InvalidAlbumArt, "Album art must be a JPEG, PNG or GIF image."
      end

      data
    end

    def number_to_human_size(bytes)
      ActiveSupport::NumberHelper.number_to_human_size(bytes)
    end

    def tags_need_writing?
      !skip_tag_write && TAG_ATTRIBUTES.any? { |attribute| will_save_change_to_attribute?(attribute) }
    end

    def write_tags_to_file
      Mp3File.new(file_path).write_attributes(slice(*TAG_ATTRIBUTES))
    rescue Mp3File::Error => e
      errors.add(:base, "Could not write tags to #{filename}: #{e.message}")
      throw :abort
    end
end
