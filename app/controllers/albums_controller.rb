class AlbumsController < ApplicationController
  def index
    # `search`, not `q`: on the song list `q` is Ransack's nested hash, and a
    # scalar `q` on a different page would read like the same parameter.
    @search = params[:search].presence
    @albums = Album.page(params[:page], search: @search)
  end

  # Unpaginated on purpose -- the largest real album is around a hundred tracks.
  def show
    @album = Album.find(params[:id])
    @songs = @album.songs
  end
end
