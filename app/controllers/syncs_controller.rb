class SyncsController < ApplicationController
  def create
    LibrarySync.enqueue(force: forced?)

    respond_to do |format|
      format.turbo_stream do
        render partial: "progress/update",
          locals: { status: ProgressReporting.current },
          formats: :turbo_stream
      end
      format.html { redirect_to root_path }
    end
  end

  private
    # A full rescan re-reads every file's tags instead of trusting timestamps.
    # Cast rather than tested for presence, so "0" and "false" mean what they say.
    def forced?
      ActiveModel::Type::Boolean.new.cast(params[:force]).present?
    end
end
