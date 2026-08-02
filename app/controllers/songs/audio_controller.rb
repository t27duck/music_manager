# The MP3 itself, served so the browser can seek in it.
#
# Deliberately not send_file or send_data. Neither implements Range: actionpack's
# data_streaming.rb never looks at HTTP_RANGE and hard-codes the status, so an
# <audio> element served by either can play a file from the start but can never
# scrub through it. Rack::Files#serving does the whole job -- 206 with
# Content-Range, 416 with `bytes */size`, multipart byteranges, Last-Modified
# with 304, and audio/mpeg from the extension.
#
# Two things not to "fix" later:
#
#   * #serving performs no root containment check. That is safe only because the
#     path comes from a Song record. Never accept a path from params here.
#   * It returns a body responding to #to_path for a 200, so Rack::Sendfile can
#     hand off to a proxy, but a plain enumerator for a 206. Anything hand-rolled
#     to replace it must get that round the same way, or a range request would be
#     answered with the whole file.
class Songs::AudioController < ApplicationController
  # Stateless. The root is consulted only by #call, which this never uses.
  FILE_SERVER = Rack::Files.new(nil)

  # Rack::Files sets this on the responses it considers failures -- including a
  # perfectly correct 416. It means "I declined; try the next route", so copying
  # it through makes Rails fall past this action and raise a routing error,
  # turning an unsatisfiable range into a 404. It is Rack plumbing, not a
  # response header.
  CASCADE_HEADER = "x-cascade".freeze

  def show
    song = Song.find(params[:song_id])
    return head :not_found unless readable?(song.file_path)

    status, headers, body = FILE_SERVER.serving(request, song.file_path)

    self.status = status
    headers.except(CASCADE_HEADER).each { |name, value| response.headers[name] = value }
    # Rack::Files does not advertise this, and without it some browsers will not
    # offer a scrub bar at all.
    response.headers["accept-ranges"] = "bytes"
    self.response_body = body
  rescue SystemCallError
    # Deleted between the check and the read.
    head :not_found
  end

  private
    def readable?(path)
      File.file?(path) && File.readable?(path)
    end
end
