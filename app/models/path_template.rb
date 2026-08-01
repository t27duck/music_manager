# Turns a song into a library-relative path, from a user-supplied template such
# as "<Artist>/<Album>/<Track:2> - <Title>".
#
# The template is untrusted input that becomes a filesystem path, so every
# segment is sanitized independently and the template itself is rejected if it
# tries to escape the library root.
class PathTemplate
  class Error < StandardError; end

  DEFAULT = "<Artist>/<Album>/<Track:2> - <Title>".freeze

  # <Token> or <Token:width> for the zero-padded numeric ones.
  TOKEN_PATTERN = /<([A-Za-z]+)(?::(\d+))?>/

  # Tokens whose value is text, and the placeholder used when a song lacks it.
  # Without a placeholder the path would collapse to an empty directory name.
  TEXT_TOKENS = {
    "Artist" => "Unknown Artist",
    "Album" => "Unknown Album",
    "Title" => "Untitled",
    "Genre" => "Unknown Genre"
  }.freeze

  # Tokens whose value is a number. A missing number renders as nothing, and the
  # segment is tidied up afterwards.
  NUMERIC_TOKENS = %w[ Year Disc Track ].freeze

  TOKENS = (TEXT_TOKENS.keys + NUMERIC_TOKENS + %w[ Filename ]).freeze

  # Characters no filesystem we care about will accept, plus control characters.
  # "/" is included because it is the separator: a token whose *value* contains
  # a slash must not silently create a directory.
  ILLEGAL_CHARACTERS = %r{[<>:"/\\|?*\x00-\x1f]}

  attr_reader :template

  def initialize(template)
    @template = template.to_s.strip
  end

  def valid?
    errors.empty?
  end

  def errors
    @errors ||= validate
  end

  # The song's new path, relative to the library root.
  def render(song)
    raise Error, errors.to_sentence unless valid?

    segments = template.split("/").filter_map { |segment| render_segment(segment, song).presence }
    raise Error, "The template produced an empty path." if segments.empty?

    File.join(*segments) + File.extname(song.file_path)
  end

  def to_s = template

  private
    def validate
      messages = []

      if template.blank?
        return [ "The template can't be blank." ]
      end

      tokens = template.scan(TOKEN_PATTERN)
      messages << "The template must use at least one token." if tokens.empty?

      unknown = tokens.map(&:first).uniq - TOKENS
      if unknown.any?
        messages << "Unknown #{'token'.pluralize(unknown.size)}: #{unknown.map { |t| "<#{t}>" }.to_sentence}."
      end

      messages << "The template can't start with a slash." if template.start_with?("/")
      messages << "The template can't contain \"..\"." if template.include?("..")

      messages
    end

    def render_segment(segment, song)
      substituted = segment.gsub(TOKEN_PATTERN) do
        value_for(Regexp.last_match(1), Regexp.last_match(2), song)
      end

      sanitize(substituted)
    end

    def value_for(token, width, song)
      case token
      when *TEXT_TOKENS.keys then song.public_send(token.downcase).presence || TEXT_TOKENS[token]
      when "Year" then pad(song.year, width)
      when "Disc" then pad(song.disc_number, width)
      when "Track" then pad(song.track_number, width)
      when "Filename" then File.basename(song.file_path.to_s, ".*")
      else ""
      end.to_s
    end

    def pad(value, width)
      return "" if value.blank?

      width.present? ? format("%0#{width}d", value) : value.to_s
    end

    # Strips characters the filesystem rejects, collapses the whitespace a
    # missing token leaves behind, and trims leading or trailing punctuation so
    # an absent track number does not produce " - Title" or a hidden dotfile.
    def sanitize(segment)
      segment
        .gsub(ILLEGAL_CHARACTERS, "")
        .gsub(/\s+/, " ")
        .sub(/\A[\s.\-_]+/, "")
        .sub(/[\s.]+\z/, "")
        .strip
    end
end
