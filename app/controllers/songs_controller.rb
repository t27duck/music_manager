class SongsController < ApplicationController
  include SongListing

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

    def song_params
      params.require(:song).permit(*Song::EDITABLE_FIELDS)
    end
end
