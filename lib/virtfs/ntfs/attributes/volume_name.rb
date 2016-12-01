require 'virt_disk/disk_unicode'

module VirtFS::NTFS
  #
  # VOLUME_NAME - Attribute: Volume name (0x60).
  #
  # NOTE: Always resident.
  # NOTE: Present only in FILE_Volume.
  #
  # Data of this class is not structured.
  #

  class VolumeName
    attr_reader :name

    def initialize(buf)
      buf   = buf.read(buf.length) if buf.kind_of?(DataRun)
      @name = buf.UnicodeToUtf8
    end

    def to_s
      @name
    end
  end # class VolumeName
end # module VirtFS::NTFS
