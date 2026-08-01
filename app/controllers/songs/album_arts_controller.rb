# The cover art embedded in a song's APIC frame.
#
# #show serves the image itself. Its URL carries the checksum, so a given URL's
# bytes can never change and the response is cached hard -- the browser fetches
# each image once and a fifty-row page does not re-read fifty MP3s on every
# scroll.
class Songs::AlbumArtsController < ApplicationController
  before_action :set_song

  def show
    return head :not_found unless @song.album_art?

    if stale?(etag: @song.album_art_checksum, public: true)
      art = @song.album_art
      return head :not_found if art.blank?

      expires_in 1.year, public: true
      send_data art, type: @song.album_art_content_type, disposition: "inline"
    end
  rescue Mp3File::Error
    head :not_found
  end

  # The art panel shown inside the edit modal.
  def edit
  end

  def update
    @song.update_album_art!(uploaded_art)
    render :update
  rescue Song::InvalidAlbumArt, Mp3File::Error => e
    @error = e.message
    render :update, status: :unprocessable_entity
  end

  def destroy
    @song.remove_album_art!
    render :update
  rescue Mp3File::Error => e
    @error = e.message
    render :update, status: :unprocessable_entity
  end

  private
    def set_song
      @song = Song.find(params[:song_id])
    end

    def uploaded_art
      file = params[:album_art]
      raise Song::InvalidAlbumArt, "Choose an image to upload." unless file.respond_to?(:read)

      file.read
    end
end
