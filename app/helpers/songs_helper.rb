module SongsHelper
  # The filters and page currently in effect, for links that must come back to
  # the same view of the list.
  def list_state_params
    state = { q: params.fetch(:q, {}).permit(*SongListing::SEARCH_KEYS).to_h.compact_blank }
    state[:page] = params[:page] if params[:page].present?
    state.compact_blank
  end

  # The same state as hidden inputs, for forms.
  def list_state_fields
    state = list_state_params
    tags = state.fetch(:q, {}).map { |key, value| hidden_field_tag("q[#{key}]", value, id: nil) }
    tags << hidden_field_tag(:page, state[:page], id: nil) if state[:page]

    safe_join(tags)
  end

  # A sortable column heading. Ransack renders the link and appends its own
  # direction arrow; this only supplies the styling.
  def sort_header(query, attribute, label)
    sort_link(query, attribute, label,
      class: "inline-flex items-center gap-1 transition hover:text-surface-100",
      data: { turbo_frame: "songs" })
  end

  # Whether the user has narrowed the list at all. Sorting does not count: it
  # changes the order, not which songs are shown.
  #
  # Scopes are not Ransack conditions, so they have to be asked for by name.
  # Both of these read the one list on Song, so a new filter cannot be added
  # without the Reset link and the advanced panel noticing it.
  def filters_active?(query)
    query.conditions.any? || scope_filters_active?(query, Song::FILTER_SCOPES)
  end

  # Whether anything in the collapsible panel is set, which decides if it opens.
  # Everything but the global search box lives in there.
  def advanced_filters_active?(query)
    query.year_eq.present? ||
      scope_filters_active?(query, Song::FILTER_SCOPES - [ "text_contains" ])
  end

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

  private
    def scope_filters_active?(query, scopes)
      scopes.any? { |scope| query.public_send(scope).present? }
    end
end
