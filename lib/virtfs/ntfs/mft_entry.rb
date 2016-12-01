# Utilities.
require 'binary_struct'
require 'virtfs/ntfs/utils'

# Attribute types & names.
require 'virtfs/ntfs/attributes/type'

# Classes.

# An attribute header preceeds each attribute.
require 'virtfs/ntfs/attributes/header'

# A data run is storage for non-resident attributes.
require 'virtfs/ntfs/data_run'

# These are the attribute types (so far these are the only types processed).
require 'virtfs/ntfs/attributes/attribute_list'
require 'virtfs/ntfs/attributes/bitmap'
require 'virtfs/ntfs/attributes/standard_information'
require 'virtfs/ntfs/attributes/file_name'
require 'virtfs/ntfs/attributes/object_id'
require 'virtfs/ntfs/attributes/volume_name'
require 'virtfs/ntfs/attributes/volume_information'
require 'virtfs/ntfs/attributes/data'
require 'virtfs/ntfs/attributes/index_root'
require 'virtfs/ntfs/attributes/index_allocation'

module VirtFS::NTFS
  #
  # MFT_RECORD - An MFT record layout
  #
  # The mft record header present at the beginning of every record in the mft.
  # This is followed by a sequence of variable length attribute records which
  # is terminated by an attribute of type AT_END which is a truncated attribute
  # in that it only consists of the attribute type code AT_END and none of the
  # other members of the attribute structure are present.
  #

  # One MFT file record, also called MFT Entry.
  FILE_RECORD = BinaryStruct.new([
    'a4', 'signature',                # Always 'FILE'
    'S',  'usa_offset',               # Offset to the Update Sequence Array (usa) from the start of the ntfs record.
    'S',  'usa_count',                # Number of u16 sized entries in the usa including the Update Sequence Number (usn),
    # thus the number of fixups is the usa_count minus 1.
    'Q',  'lsn',                      # $LogFile sequence number for this record.
    # Changed every time the record is modified
    'S',  'seq_num',                  # Number of times this MFT record has been reused
    'S',  'hard_link_count',          # Number of links to this file
    'S',  'offset_to_attrib',         # Byte offset to the first attribute in this mft record from the start of the mft record.
    # NOTE: Must be aligned to 8-byte boundary.
    'S',  'flags',                    # File record flags
    'L',  'bytes_in_use',             # Number of bytes used in this mft record.
    # NOTE: Must be aligned to 8-byte boundary.
    'L',  'bytes_allocated',          # Number of bytes allocated for this mft record. This should be equal
    # to the mft record size
    'Q',  'base_mft_record',          # This is zero for base mft records. When it is not zero it is a mft reference
    # pointing to the base mft record to which this record belongs (this is then
    # used to locate the attribute list attribute present in the base record which
    # describes this extension record and hence might need modification when the
    # extension record itself is modified, also locating the attribute list also
    # means finding the other potential extents, belonging to the non-base mft record).
    'S',  'next_attrib_id',           # The instance number that will be assigned to the next attribute added to this
    # mft record.
    # NOTE: Incremented each time after it is used.
    # NOTE: Every time the mft record is reused this number is set to zero.
    # NOTE: The first instance number is always 0

    #
    # The 2 fields below are specific to NTFS 3.1+ (Windows XP and above):
    #
    'S',  'unused1',                  # Reserved/alignment
    'L',  'mft_rec_num',              # Number of this mft record.

    # When (re)using the mft record, we place the update sequence array at this
    # offset, i.e. before we start with the attributes. This also makes sense,
    # otherwise we could run into problems with the update sequence array
    # containing in itself the last two bytes of a sector which would mean that
    # multi sector transfer protection wouldn't work. As you can't protect data
    # by overwriting it since you then can't get it back...
    # When reading we obviously use the data from the ntfs record header.
    #
    'S',  'fixup_seq_num',            # Magic word at end of sector
  ])
  # Here follows the fixup array (WORD).
  SIZEOF_FILE_RECORD = FILE_RECORD.size

  # MftEntry represents one single MFT entry.
  class MftEntry
    attr_reader :sequence_num, :rec_num, :boot_sector, :mft_entry, :attribs

    MFT_RECORD_IN_USE        = 0x0001  # Not set if file has been deleted
    MFT_RECORD_IS_DIRECTORY  = 0x0002  # Set if record describes a directory
    MFT_RECORD_IS_4          = 0x0004  # MFT_RECORD_IS_4 exists on all $Extend sub-files.  It seems that it marks it is a metadata file with MFT record >24, however, it is unknown if it is limited to metadata files only.
    MFT_RECORD_IS_VIEW_INDEX = 0x0008  # MFT_RECORD_IS_VIEW_INDEX exists on every metafile with a non directory index, that means an INDEX_ROOT and an INDEX_ALLOCATION with a name other than "$I30". It is unknown if it is limited to metadata files only.

    EXPECTED_SIGNATURE       = 'FILE'

    def initialize(bs, record_number)
      raise "nil boot sector" if bs.nil?

      @attribs         = []
      @attribs_by_type = Hash.new { |h, k| h[k] = [] }

      # Buffer boot sector & seek to requested record.
      @boot_sector = bs
      bs.stream.seek(bs.mft_rec_to_byte_pos(record_number))

      # Get & decode the FILE_RECORD.
      @buf       = bs.stream.read(bs.bytes_per_file_rec)
      @mft_entry = FILE_RECORD.decode(@buf)

      # Adjust for older versions (don't have unused1 and mft_rec_num).
      version = bs.version
      if !version.nil? && version < 4.0
        @mft_entry['fixup_seq_num'] = @mft_entry['unused1']
        @mft_entry['mft_rec_num']   = record_number
      end

      # Set accessor data.
      @sequence_num = @mft_entry['seq_num']
      @rec_num      = @mft_entry['mft_rec_num']
      @flags        = @mft_entry['flags']

      begin
        # Check for proper signature.
        VirtFS::NTFS::Utils.validate_signature(@mft_entry['signature'], EXPECTED_SIGNATURE)
        # Process per-sector "fixups" that NTFS uses to detect corruption of multi-sector data structures
        @buf = VirtFS::NTFS::Utils.process_fixups(@buf, @boot_sector.bytes_per_sector, @mft_entry['usa_offset'], @mft_entry['usa_count'])
      rescue => err
        emsg = "Invalid MFT Entry <#{record_number}> because: <#{err.message}>"
        raise emsg
      end

      @buf = @buf[@mft_entry['offset_to_attrib']..-1]

      attribute_headers
    end

    # For string rep, if valid return record number.
    def to_s
      @mft_entry['mft_rec_num'].to_s
    end

    def deleted?
      !VirtFS::NTFS::Utils.bit?(@flags, MFT_RECORD_IN_USE)
    end

    def dir?
      VirtFS::NTFS::Utils.bit?(@flags, MFT_RECORD_IS_DIRECTORY)
    end

    def index_root
      if @index_root.nil?
        @index_root             = first_attribute(AT_INDEX_ROOT)
        @index_root.bitmap      = first_attribute(AT_BITMAP)      unless @index_root.nil?
        @index_root.allocations = get_attributes(AT_INDEX_ALLOCATION) unless @index_root.nil?
      end

      @index_root
    end

    def attribute_data
      if @attribute_data.nil?
        dataArray = get_attributes(AT_DATA)

        unless dataArray.nil?
          dataArray.compact!
          if dataArray.size > 0
            @attribute_data = dataArray.shift
            dataArray.each { |datum| @attribute_data.data.addRun(datum.run) }
          end
        end
      end

      @attribute_data
    end

    def root_attribute_data
      load_first_attribute(AT_DATA)
    end

    def attribute_list
      @attribute_list ||= load_first_attribute(AT_ATTRIBUTE_LIST)
    end

    def attribute_headers
      offset = 0
      while h = AttribHeader.new(@buf[offset..-1])
        break if h.type.nil? || h.type == AT_END
        attrib = {"type" => h.type, "offset" => offset, "header" => h}
        @attribs << attrib
        @attribs_by_type[h.type] << attrib
        offset += h.length
      end
    end

    def first_attribute(attribType)
      get_attributes(attribType).first
    end

    def get_attributes(attribType)
      attribute_list.nil? ? attributes(attribType) : attribute_list.attributes(attribType)
    end

    def load_first_attribute(attribType)
      attributes(attribType).first
    end

    def attributes(attribType)
      result  = []
      if @attribs_by_type.key?(attribType)
        @attribs_by_type[attribType].each do |attrib|
          attrib["attr"] = create_attribute(attrib["offset"], attrib["header"]) unless attrib.key?('attr')
          result << attrib["attr"]
        end
      end
      result
    end

    def create_attribute(offset, header)
      buf = header.get_value(@buf[offset..-1], @boot_sector)

      return StandardInformation.new(buf)                             if header.type == AT_STANDARD_INFORMATION
      return FileName.new(buf)                                        if header.type == AT_FILE_NAME
      return ObjectId.new(buf)                                        if header.type == AT_OBJECT_ID
      return VolumeName.new(buf)                                      if header.type == AT_VOLUME_NAME
      return VolumeInformation.new(buf)                               if header.type == AT_VOLUME_INFORMATION
      return AttributeList.new(buf, @boot_sector)                     if header.type == AT_ATTRIBUTE_LIST
      return AttribData.from_header(header, buf)                      if header.type == AT_DATA
      return IndexRoot.from_header(header, buf, @boot_sector)         if header.type == AT_INDEX_ROOT
      return IndexAllocation.from_header(header, buf)                 if header.type == AT_INDEX_ALLOCATION
      return Bitmap.from_header(header, buf)                          if header.type == AT_BITMAP

      # Attribs are unrecognized if they don't appear in TypeName.
      unless TypeName.key?(header.type)
        msg = "MIQ(NTFS::MftEntry.create_attribute) Unrecognized attribute type: 0x#{'%08x' % header.type} -- header: #{header.inspect}"
        raise(msg)
      end

      nil
    end
  end # class MftEntry
end # module VirtFS::NTFS
