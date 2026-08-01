class Song < ApplicationRecord
  # Attributes mirrored into the file's ID3 tags whenever they change.
  TAG_ATTRIBUTES = Mp3File::TAG_ATTRIBUTES

  # Metadata fields the user can edit, in display order.
  EDITABLE_FIELDS = %w[ title artist album genre year disc_number track_number ].freeze

  # Fields the "missing metadata" filter can look for.
  MISSING_METADATA_FIELDS = %w[ artist album genre year ].freeze

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

  # Searching file paths needs the same ESCAPE treatment, and for the same
  # reason: paths are full of underscores, and Ransack's built-in `cont` would
  # let every one of them match any character.
  scope :file_path_contains, ->(value) {
    next all if value.blank?

    where("file_path LIKE ? ESCAPE ?", "%#{sanitize_sql_like(value)}%", "\\")
  }

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
    %w[ file_path_contains missing_metadata ]
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

  private
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
