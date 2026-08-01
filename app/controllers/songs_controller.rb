class SongsController < ApplicationController
  # Every search key the UI can produce. Ransack allow-lists attributes and
  # scopes of its own accord, but permitting explicitly here means an unknown
  # key is dropped before Ransack ever sees it.
  SEARCH_KEYS = %i[
    title_or_artist_or_album_or_genre_cont
    title_cont artist_cont album_cont genre_cont year_eq
    file_path_contains missing_metadata s
  ].freeze

  before_action :set_song, only: [ :edit, :update, :destroy ]

  def index
    load_songs
  end

  def edit
  end

  def update
    if @song.update(song_params)
      # The edit may have moved the song out of the current filter or changed
      # its position, so the whole list is re-rendered from the filters and page
      # the form carried along.
      load_songs
      render :update
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @song.destroy_with_file!
    load_songs

    render :destroy
  rescue SystemCallError => e
    render :destroy_failed, locals: { message: e.message }, status: :unprocessable_entity
  end

  private
    def set_song
      @song = Song.find(params[:id])
    end

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

    def song_params
      params.require(:song).permit(*Song::EDITABLE_FIELDS)
    end
end
