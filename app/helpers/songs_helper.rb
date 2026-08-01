module SongsHelper
  # 154 -> "2:34", 3725 -> "1:02:05". Blank durations render as a dash so the
  # column stays aligned.
  def formatted_duration(seconds)
    return "—" if seconds.blank?

    hours, remainder = seconds.divmod(3600)
    minutes, secs = remainder.divmod(60)

    if hours.positive?
      format("%d:%02d:%02d", hours, minutes, secs)
    else
      format("%d:%02d", minutes, secs)
    end
  end

  def formatted_file_size(bytes)
    return "—" if bytes.blank?

    number_to_human_size(bytes)
  end

  # Track numbers read better as plain digits, but a missing one should not
  # leave an empty cell.
  def formatted_track(song)
    return "—" if song.track_number.blank?
    return song.track_number.to_s if song.disc_number.blank?

    "#{song.disc_number}-#{song.track_number}"
  end

  # Any metadata value that may be missing.
  def metadata_value(value)
    return tag.span("—", class: "text-surface-600") if value.blank?

    value.to_s
  end
end
