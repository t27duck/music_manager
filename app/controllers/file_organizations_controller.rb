class FileOrganizationsController < ApplicationController
  include SongListing

  before_action :set_selected_songs
  before_action :set_template

  # Also the preview: the template form re-renders this action into a frame as
  # the user types, so what they read is exactly what #create will do.
  # Previewing every move in a selection of thousands would render the whole
  # library one line at a time; the rest is summarised instead.
  def new
    @moves = @organizer.preview(@selected_songs.first(SongListing::PREVIEW_LIMIT))
    render :new, status: (@error ? :unprocessable_entity : :ok)
  end

  def create
    if @error
      return render :new, status: :unprocessable_entity
    end

    if @selected_songs.empty?
      @error = "Select some songs to organize."
      return render :new, status: :unprocessable_entity
    end

    unless @template.valid?
      @error = @template.errors.to_sentence
      return render :new, status: :unprocessable_entity
    end

    # Ids are resolved here rather than in the job: once files start moving, a
    # filter re-run mid-flight would match a different set.
    enqueued = FileOrganization.enqueue(
      song_ids: @selected_songs.map(&:id), template: @template.to_s
    )

    unless enqueued
      @error = "Something else is already running — try again when it finishes."
      return render :new, status: :unprocessable_entity
    end

    render :create
  end

  private
    def set_selected_songs
      if selection_too_large?
        @error = selection_too_large_message
        @selected_songs = []
      else
        @selected_songs = selected_songs
      end
    end

    # What the user is typing, else what they last applied, else the default.
    def set_template
      @template = PathTemplate.new(params[:template].presence || Setting[:path_template] || PathTemplate::DEFAULT)
      @organizer = FileOrganizer.new(@template)
      @moves = []
    end
end
