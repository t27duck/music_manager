class BulkUpdatesController < ApplicationController
  include SongListing

  before_action :set_selected_songs

  def new
  end

  def create
    bulk_update = Song::BulkUpdate.new(@selected_songs,
      attributes: bulk_params, album_art: uploaded_art, remove_album_art: remove_album_art?)

    if @selected_songs.empty? || !bulk_update.changes?
      @error = "Choose at least one change to apply."
      return render :new, status: :unprocessable_entity
    end

    @result = bulk_update.call
    load_songs

    render :create
  end

  private
    def set_selected_songs
      @selected_songs = Song.where(id: params[:song_ids]).ordered.to_a
    end

    def bulk_params
      params.fetch(:bulk_update, {}).permit(*Song::BulkUpdate::FIELDS).to_h
    end

    def uploaded_art
      params[:album_art].respond_to?(:read) ? params[:album_art].read : nil
    end

    def remove_album_art?
      ActiveModel::Type::Boolean.new.cast(params[:remove_album_art]).present?
    end
end
