# Filesystem-safe path segments.
#
# Both the path templates and the uploader turn untrusted strings into file
# names, so the character rules live in one place rather than drifting apart in
# two -- one of them guards against directory traversal.
module SafeFilename
  # Characters no filesystem we care about accepts, plus control characters.
  # "/" is included because a value containing one must never silently become a
  # directory separator.
  ILLEGAL_CHARACTERS = %r{[<>:"/\\|?*\x00-\x1f]}

  # A single path component, stripped of anything illegal. Returns "" when
  # nothing usable is left.
  def self.sanitize_segment(segment)
    segment.to_s
      .gsub(ILLEGAL_CHARACTERS, "")
      .gsub(/\s+/, " ")
      .sub(/[\s.]+\z/, "")   # trailing dots and spaces break on Windows
      .sub(/\A[\s.]+/, "")   # a leading dot would make a hidden file
      .strip
  end

  # Splits a client-supplied relative path into sanitized segments, discarding
  # "." and ".." outright. The result can never climb out of its destination.
  def self.sanitize_path(relative_path)
    relative_path.to_s.split(%r{[/\\]}).filter_map do |segment|
      next if segment.in?([ ".", ".." ])

      sanitize_segment(segment).presence
    end
  end
end
