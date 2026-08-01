class SongsController < ApplicationController
  def index
    @songs = Song.ordered.page(params[:page])
  end
end
