# Creates or refreshes the Song record for one MP3 on disk.
#
# Used by both the library sync and the uploader. Because it reads tags *from*
# the file, it sets skip_tag_write so Song's write-through callback does not
# immediately write the same values back.
class SongImporter
  attr_reader :path

  def self.call(path)
    new(path).call
  end

  def initialize(path)
    @path = File.expand_path(path.to_s)
  end

  # Returns the persisted Song. Raises Mp3File::Error if the file cannot be read
  # and ActiveRecord::RecordInvalid if it cannot be saved; the sync catches both
  # per file so one bad MP3 cannot abort a whole run.
  def call
    song = Song.find_or_initialize_by(file_path: path)

    song.skip_tag_write = true
    song.assign_attributes(attributes)
    song.save!
    song
  end

  private
    def attributes
      tags = Mp3File.new(path).attributes
      stat = File.stat(path)

      tags.merge(
        title: tags[:title].presence || default_title,
        file_size: stat.size,
        file_modified_at: stat.mtime,
        last_seen_at: Time.current
      )
    end

    # "Default to filename if no title tag found" -- without the extension.
    def default_title
      File.basename(path, ".*")
    end
end
