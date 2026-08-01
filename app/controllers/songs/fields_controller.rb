# A single editable cell in the song list, edited in place.
#
# Only the cell is re-rendered, not the whole list: inline editing is meant to
# be quick, and replacing the table under the user on every keystroke-sized edit
# would defeat that. Use the modal (SongsController#update) when the change
# should be reflected in filters and ordering.
class Songs::FieldsController < ApplicationController
  before_action :set_song
  before_action :set_name

  def show
    render_cell
  end

  def edit
  end

  def update
    if @song.update(name => field_value)
      render_cell
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    attr_reader :name

    def set_song
      @song = Song.find(params[:song_id])
    end

    # Anything outside the editable set is a 404 rather than a silent no-op.
    def set_name
      @name = params[:name].to_s

      raise ActionController::RoutingError, "Unknown field #{@name}" unless
        Song::EDITABLE_FIELDS.include?(@name)
    end

    def field_value
      params.require(:song).permit(name)[name]
    end

    def render_cell
      render partial: "songs/fields/field", locals: { song: @song, name: name }
    end
end
