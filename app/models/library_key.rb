# The URL key for a grouped view of the library.
#
# Albums and artists are not records: an album *is* the pair
# (album_artist, album), so the pair itself has to round-trip through the URL.
#
# JSON inside urlsafe Base64 rather than a delimiter, because the values are
# arbitrary user tags: a delimiter can appear inside a name, and only JSON
# round-trips nil (there are songs with no album, and they still need a page).
# The result is opaque but exact, and needs no lookup table.
#
# Anything malformed raises RecordNotFound, so a hand-edited URL is a 404 rather
# than a 500.
module LibraryKey
  def self.encode(*parts)
    Base64.urlsafe_encode64(JSON.generate(parts), padding: false)
  end

  def self.decode(param, size)
    parts = JSON.parse(Base64.urlsafe_decode64(param.to_s))

    unless parts.is_a?(Array) && parts.size == size &&
        parts.all? { |part| part.nil? || (part.is_a?(String) && part.valid_encoding?) }
      raise ActiveRecord::RecordNotFound, "Malformed key: #{param.inspect}"
    end

    parts
  rescue ArgumentError, JSON::ParserError
    raise ActiveRecord::RecordNotFound, "Malformed key: #{param.inspect}"
  end
end
