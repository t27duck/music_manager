# Loading the song list the way the user last saw it.
#
# Shared by every controller that answers with a re-rendered list, so that a
# bulk update or a file move comes back with the same filters, sorting and page
# the user was looking at.
module SongListing
  extend ActiveSupport::Concern

  # Every search key the UI can produce. Ransack allow-lists attributes and
  # scopes of its own accord, but permitting explicitly here means an unknown
  # key is dropped before Ransack ever sees it.
  SEARCH_KEYS = %i[
    title_or_artist_or_album_or_genre_cont
    title_cont artist_cont album_cont genre_cont year_eq
    file_path_contains missing_metadata s
  ].freeze

  private
    def load_songs
      @query = Song.ransack(search_params)

      # Ransack only takes over the ordering once the user has clicked a column;
      # until then the library reads in its natural order, which is more than
      # one column deep and so cannot be expressed as a single default sort.
      results = @query.result
      results = results.ordered if @query.sorts.empty?

      @songs = results.page(params[:page])
    end

    def search_params
      params.fetch(:q, {}).permit(*SEARCH_KEYS).to_h.compact_blank
    end
end
