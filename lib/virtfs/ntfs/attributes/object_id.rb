require 'virt_disk/disk_uuid'

module VirtFS::NTFS
  # There is no real data definition for this class - it consists entirely of GUIDs.
  #
  # struct GUID - GUID structures store globally unique identifiers (GUID).
  #
  # A GUID is a 128-bit value consisting of one group of eight hexadecimal
  # digits, followed by three groups of four hexadecimal digits each, followed
  # by one group of twelve hexadecimal digits. GUIDs are Microsoft's
  # implementation of the distributed computing environment (DCE) universally
  # unique identifier (UUID).
  #
  # Example of a GUID:
  #  1F010768-5A73-BC91-0010-A52216A7227B
  #

  class ObjectId
    attr_reader :object_id, :birth_volume_id, :birth_object_id, :domain_Id

    def initialize(buf)
      raise "nil buffer" if buf.nil?

      buf = buf.read(buf.length) if buf.kind_of?(DataRun)
      len = 16
      @object_id        = DiskUUID.parse_raw(buf[len * 0, len])
      @birth_volume_id  = DiskUUID.parse_raw(buf[len * 1, len]) if buf.length > 16
      @birth_object_id  = DiskUUID.parse_raw(buf[len * 2, len]) if buf.length > 16
      @domain_Id        = DiskUUID.parse_raw(buf[len * 3, len]) if buf.length > 16
    end
  end # class ObjectID
end # module VirtFS::NTFS
