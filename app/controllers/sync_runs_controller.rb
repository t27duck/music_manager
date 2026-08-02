class SyncRunsController < ApplicationController
  # Sync history, newest first. Retention caps the table at SyncRun::KEEP, so
  # this is a handful of pages by construction.
  def index
    @runs = SyncRun.recent.page(params[:page])
  end
end
