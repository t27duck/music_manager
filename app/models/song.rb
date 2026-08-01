class Song < ApplicationRecord
  # Attributes mirrored into the file's ID3 tags whenever they change.
  TAG_ATTRIBUTES = Mp3File::TAG_ATTRIBUTES

  # Metadata fields the user can edit, in display order.
  EDITABLE_FIELDS = %w[ title artist album genre year disc_number track_number ].freeze

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

  scope :ordered, -> { order(:artist, :album, :disc_number, :track_number, :title) }

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
