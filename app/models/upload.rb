# One uploaded MP3, saved into the library's _NEW directory and imported.
#
# The relative path comes from the browser (a dragged folder's structure), so it
# is treated as hostile: every segment is sanitized, "." and ".." are discarded,
# and the resolved destination is re-checked against _NEW before anything is
# written.
class Upload
  class Error < StandardError; end

  DESTINATION = "_NEW".freeze
  EXTENSION = ".mp3".freeze

  attr_reader :file, :relative_path

  def initialize(file:, relative_path: nil)
    @file = file
    @relative_path = relative_path.presence || (file.respond_to?(:original_filename) ? file.original_filename : nil)
  end

  # Writes the file and returns the imported Song.
  def save!
    validate!

    target = destination
    FileUtils.mkdir_p(File.dirname(target))
    write(target)

    SongImporter.call(target)
  rescue Mp3File::Error => e
    # The bytes made it to disk but are not really an MP3; do not leave it there.
    FileUtils.rm_f(target) if target
    raise Error, "Not a readable MP3 file (#{e.message})."
  end

  def filename
    segments.last
  end

  private
    def validate!
      raise Error, "No file was uploaded." unless file.respond_to?(:read)
      raise Error, "Only MP3 files can be uploaded." unless mp3_extension?
      raise Error, "The file name is not usable." if segments.empty?
    end

    def mp3_extension?
      File.extname(relative_path.to_s).downcase == EXTENSION
    end

    def segments
      @segments ||= SafeFilename.sanitize_path(relative_path)
    end

    def new_root
      @new_root ||= File.expand_path(File.join(Configuration.library_root, DESTINATION))
    end

    # Belt and braces: sanitize_path already drops "..", but the resolved path is
    # checked again so a future change to the sanitizer cannot open a hole.
    def destination
      target = File.expand_path(File.join(new_root, *segments))

      unless target.start_with?(new_root + File::SEPARATOR)
        raise Error, "The file path is not allowed."
      end

      target
    end

    def write(target)
      file.rewind if file.respond_to?(:rewind)

      File.open(target, "wb") do |output|
        IO.copy_stream(file.respond_to?(:tempfile) ? file.tempfile : file, output)
      end
    end
end
