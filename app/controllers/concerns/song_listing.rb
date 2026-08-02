# Loading the song list the way the user last saw it, and resolving the
# selection made against it.
#
# Shared by every controller that answers with a re-rendered list, so that a
# bulk update or a file move comes back with the same filters, sorting and page
# the user was looking at.
module SongListing
  extend ActiveSupport::Concern

  # Every search key the UI can produce. Ransack allow-lists attributes and
  # scopes of its own accord, but permitting explicitly here means an unknown
  # key is dropped before Ransack ever sees it.
  # The text filters are Song scopes rather than Ransack predicates, because
  # only a scope can emit the ESCAPE that SQLite's LIKE needs. `year_eq` is a
  # real Ransack condition and `s` is the sort.
  SEARCH_KEYS = (Song::FILTER_SCOPES.map(&:to_sym) + %i[ year_eq s ]).freeze

  # How many songs one action may touch. Refused rather than truncated: doing
  # part of what was asked, silently, is worse than doing none of it.
  SELECTION_LIMIT = 5_000

  # How many songs a modal lists or previews before summarising the rest. The
  # whole library rendered one <li> at a time is not a preview.
  PREVIEW_LIMIT = 100

  private
    def load_songs
      @query = Song.ransack(search_params)
      @songs = ordered_result(@query).page(params[:page])
    end

    # The songs the user's selection refers to.
    #
    # Two modes: explicit ids for the usual case, and -- when the user asked for
    # everything matching -- the filter itself, re-resolved here. The second
    # exists because a selection of thousands cannot travel as ids in a URL, and
    # because the browser has never seen most of those rows.
    def selected_songs
      @selected_songs ||= select_all? ? selection_scope.to_a : Song.where(id: params[:song_ids]).ordered.to_a
    end

    # Deliberately never paged: selecting everything matching spans pages by
    # definition. Shares its ordering with #load_songs so the list the user read
    # and the set they act on can never disagree.
    def selection_scope
      ordered_result(Song.ransack(search_params))
    end

    def select_all?
      ActiveModel::Type::Boolean.new.cast(params[:select_all]).present?
    end

    # True when the selection is bigger than one action may touch.
    def selection_too_large?
      select_all? && selection_scope.count > SELECTION_LIMIT
    end

    def selection_too_large_message
      "That would affect #{number_with_delimiter(selection_scope.count)} songs. " \
        "Narrow your filters to #{number_with_delimiter(SELECTION_LIMIT)} or fewer."
    end

    # Ransack only takes over the ordering once the user has clicked a column;
    # until then the library reads in its natural order, which is more than one
    # column deep and so cannot be expressed as a single default sort.
    def ordered_result(query)
      query.sorts.empty? ? query.result.ordered : query.result
    end

    def search_params
      params.fetch(:q, {}).permit(*SEARCH_KEYS).to_h.compact_blank
    end

    def number_with_delimiter(number)
      ActiveSupport::NumberHelper.number_to_delimited(number)
    end
end
