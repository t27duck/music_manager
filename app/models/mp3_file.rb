# The single point of contact between the application and the ruby-mp3info gem.
#
# Everything else works with plain Song attributes; this class knows how ID3v1
# and ID3v2 frames map onto them, and how to defend against the malformed tags
# real-world MP3s are full of (invalid UTF-8, embedded NUL bytes, "3/12" track
# numbers, "1999-01-01" years).
class Mp3File
  # Raised for anything the caller can reasonably surface to a user: a missing,
  # unreadable, or corrupt file. Callers rescue this rather than Mp3InfoError.
  class Error < StandardError; end

  # Song attributes written back into the file's tags.
  TAG_ATTRIBUTES = %w[ title artist album genre year track_number disc_number ].freeze

  # ruby-mp3info's generic tag keys, which it mirrors into both ID3v1 and ID3v2.3
  # when the file is closed. Disc number has no generic key -- see #write_attributes.
  GENERIC_TAG_KEYS = {
    title: "title",
    artist: "artist",
    album: "album",
    genre: "genre_s",
    year: "year",
    track_number: "tracknum"
  }.freeze

  NULL_BYTE = "\u0000".freeze

  attr_reader :path

  def initialize(path)
    @path = path.to_s
  end

  # Every attribute that can be derived from the file, ready to assign to a Song.
  def attributes
    open do |mp3|
      art = picture_data(mp3)

      {
        title: sanitize(mp3.tag.title),
        artist: sanitize(mp3.tag.artist),
        album: sanitize(mp3.tag.album),
        genre: sanitize(mp3.tag.genre_s),
        year: parse_year(mp3.tag.year),
        track_number: parse_number(mp3.tag.tracknum),
        disc_number: parse_number(mp3.tag2["disc_number"] || mp3.tag2["TPOS"]),
        duration: mp3.length&.round,
        bitrate: mp3.bitrate&.round,
        album_art_checksum: art && Digest::MD5.hexdigest(art),
        album_art_content_type: art && self.class.image_content_type(art)
      }
    end
  end

  # Writes the given Song attributes into the file's tags. ruby-mp3info mirrors
  # the generic keys into ID3v1 and ID3v2.3 on close; disc number has no generic
  # key, so it is written straight to the TPOS frame.
  def write_attributes(attributes)
    attributes = attributes.symbolize_keys

    open do |mp3|
      GENERIC_TAG_KEYS.each do |attribute, tag_key|
        next unless attributes.key?(attribute)

        if (value = attributes[attribute].presence)
          mp3.tag[tag_key] = value
        else
          clear_tag(mp3, tag_key)
        end
      end

      if attributes.key?(:disc_number)
        mp3.tag2["TPOS"] = attributes[:disc_number].presence&.to_s
      end
    end
  end

  # The raw bytes of the first embedded picture, or nil when the file has no art.
  def album_art
    open { |mp3| picture_data(mp3) }
  end

  # ID3 tags routinely contain bytes that are not valid UTF-8, and NULs left over
  # from fixed-width ID3v1 fields. Both would blow up on the way into SQLite, so
  # scrub them here rather than at every call site. Returns nil for blank values.
  def self.sanitize_string(value)
    return nil if value.nil?

    string = value.to_s.dup.force_encoding(Encoding::UTF_8)
    string = string.scrub("") unless string.valid_encoding?
    string.delete(NULL_BYTE).strip.presence
  end

  def self.image_content_type(data)
    header = data.byteslice(0, 4).b

    if header.start_with?("\x89PNG".b) then "image/png"
    elsif header.start_with?("GIF8".b) then "image/gif"
    elsif header.start_with?("\xFF\xD8".b) then "image/jpeg"
    else "application/octet-stream"
    end
  end

  private
    def open(&block)
      raise Error, "File not found: #{path}" unless File.exist?(path)

      Mp3Info.open(path, &block)
    rescue Mp3InfoError, Errno::ENOENT, Errno::EACCES, IOError => e
      raise Error, e.message
    end

    def picture_data(mp3)
      # #pictures returns [[filename, data], ...]; we only keep the first image.
      mp3.tag2.pictures.first&.last.presence
    rescue StandardError
      # A malformed APIC frame must not make the rest of the file unreadable.
      nil
    end

    def sanitize(value)
      self.class.sanitize_string(value)
    end

    # ruby-mp3info only copies truthy generic values into the ID3v1 and ID3v2
    # tags on close, so assigning nil leaves the old frame in place. Clearing a
    # field means deleting it from all three places.
    def clear_tag(mp3, tag_key)
      mp3.tag.delete(tag_key)
      mp3.tag1.delete(tag_key)
      mp3.tag2.delete(Mp3Info::TAG_MAPPING_2_3[tag_key])
    end

    # Years arrive as 1999, "1999", or "1999-01-01"; anything else is noise.
    def parse_year(value)
      year = sanitize(value)&.slice(/\d{4}/)&.to_i
      year if year&.positive?
    end

    # Track and disc numbers arrive as 3, "3", or "3/12".
    def parse_number(value)
      number = sanitize(value)&.slice(/\d+/)&.to_i
      number if number&.positive?
    end
end
