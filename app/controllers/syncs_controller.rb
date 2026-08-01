class SyncsController < ApplicationController
  # The live status. Broadcasts keep open pages current; this exists so a page
  # can also ask for the status directly.
  def show
    render_status
  end

  def create
    LibrarySync.enqueue

    respond_to do |format|
      format.turbo_stream { render_status }
      format.html { redirect_to root_path }
    end
  end

  private
    # The same partial the broadcast renders, so a direct request and a live
    # update produce identical markup.
    def render_status
      render partial: "syncs/update",
        locals: { status: LibrarySync.status },
        formats: :turbo_stream
    end
end
