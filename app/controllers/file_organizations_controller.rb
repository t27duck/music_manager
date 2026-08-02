class FileOrganizationsController < ApplicationController
  include SongListing

  before_action :set_selected_songs
  before_action :set_template

  # Also the preview: the template form re-renders this action into a frame as
  # the user types, so what they read is exactly what #create will do.
  def new
    @moves = @organizer.preview(@selected_songs)
  end

  def create
    if @selected_songs.empty?
      @error = "Select some songs to organize."
      return render :new, status: :unprocessable_entity
    end

    unless @template.valid?
      @error = @template.errors.to_sentence
      return render :new, status: :unprocessable_entity
    end

    @result = @organizer.apply!(@selected_songs)

    # Remembered only once the moves have actually been made, and outside the
    # transaction that made them: a template that failed to save is a better
    # outcome than one remembered for moves that never happened.
    Setting[:path_template] = @template.to_s
    load_songs

    render :create
  end

  private
    def set_selected_songs
      @selected_songs = Song.where(id: params[:song_ids]).ordered.to_a
    end

    # What the user is typing, else what they last applied, else the default.
    def set_template
      @template = PathTemplate.new(params[:template].presence || Setting[:path_template] || PathTemplate::DEFAULT)
      @organizer = FileOrganizer.new(@template)
      @moves = []
    end
end
