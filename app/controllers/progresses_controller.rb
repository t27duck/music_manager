class ProgressesController < ApplicationController
  # The live progress of whatever is running. Broadcasts keep open pages
  # current; this exists so a page can also ask directly, which is how
  # progress_controller.js recovers from a broadcast it missed.
  def show
    render partial: "progress/update",
      locals: { status: ProgressReporting.current },
      formats: :turbo_stream
  end
end
