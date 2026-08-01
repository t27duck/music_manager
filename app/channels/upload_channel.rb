# Per-file results for one upload session.
#
# The stream is scoped by an id the browser generates, so two tabs uploading at
# once never see each other's messages.
class UploadChannel < ApplicationCable::Channel
  def self.stream_name_for(upload_id)
    "uploads:#{upload_id}"
  end

  def self.broadcast_result(upload_id:, status:, filename:, message:)
    return if upload_id.blank?

    ActionCable.server.broadcast(stream_name_for(upload_id),
      { status: status, filename: filename, message: message })
  end

  def subscribed
    return reject if params[:upload_id].blank?

    stream_from self.class.stream_name_for(params[:upload_id])
  end
end
