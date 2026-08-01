class UploadsController < ApplicationController
  # The drag-and-drop page.
  def show
  end

  # One file per request, so the browser can report progress per file and one
  # bad file cannot fail the rest.
  def create
    upload = Upload.new(file: params[:file], relative_path: params[:relative_path])
    song = upload.save!

    broadcast(:success, upload.filename, "Imported #{song.title}")
    render json: { status: "ok", filename: upload.filename, title: song.title }, status: :created
  rescue Upload::Error, ActiveRecord::RecordInvalid => e
    filename = upload&.filename || "file"
    broadcast(:error, filename, e.message)
    render json: { status: "error", filename: filename, message: e.message },
      status: :unprocessable_entity
  end

  private
    def broadcast(status, filename, message)
      UploadChannel.broadcast_result(
        upload_id: params[:upload_id], status: status, filename: filename, message: message
      )
    end
end
