class BulkUpdatesController < ApplicationController
  include SongListing

  before_action :set_selected_songs

  def new
  end

  def create
    if @selected_songs.empty? || !changes?
      @error = "Choose at least one change to apply."
      return render :new, status: :unprocessable_entity
    end

    # The work happens in a job: every changed song has its ID3 tags rewritten,
    # which is a whole-file rewrite, so a large selection cannot be applied
    # inside the request.
    enqueued = BulkEdit.enqueue(
      song_ids: @selected_songs.map(&:id),
      attributes: bulk_params,
      album_art_path: BulkEdit.spool_album_art(uploaded_art),
      remove_album_art: remove_album_art?
    )

    unless enqueued
      @error = "Something else is already running — try again when it finishes."
      return render :new, status: :unprocessable_entity
    end

    render :create
  end

  private
    def set_selected_songs
      @selected_songs = Song.where(id: params[:song_ids]).ordered.to_a
    end

    def bulk_params
      @bulk_params ||= params.fetch(:bulk_update, {}).permit(*Song::BulkUpdate::FIELDS).to_h
    end

    # Memoized because the upload is an IO: reading it twice returns "" the
    # second time, and the art would be silently dropped.
    def uploaded_art
      return @uploaded_art if defined?(@uploaded_art)

      @uploaded_art = params[:album_art].respond_to?(:read) ? params[:album_art].read : nil
    end

    def remove_album_art?
      ActiveModel::Type::Boolean.new.cast(params[:remove_album_art]).present?
    end

    # Song::BulkUpdate owns what counts as a change, so ask it rather than
    # reimplementing the rule here.
    def changes?
      Song::BulkUpdate.new([],
        attributes: bulk_params,
        album_art: uploaded_art,
        remove_album_art: remove_album_art?).changes?
    end
end
