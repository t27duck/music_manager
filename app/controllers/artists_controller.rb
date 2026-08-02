class ArtistsController < ApplicationController
  def index
    @search = params[:search].presence
    @artists = Artist.page(params[:page], search: @search)
  end

  def show
    @artist = Artist.find(params[:id])
    @albums = @artist.albums
  end
end
