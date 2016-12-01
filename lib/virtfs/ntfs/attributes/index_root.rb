require 'binary_struct'
require 'virt_disk/disk_unicode'
require 'virtfs/ntfs/index_node_header'
require 'virtfs/ntfs/directory_index_node'
require 'virtfs/ntfs/index_record_header'

module VirtFS::NTFS
  #
  # INDEX_ROOT - Attribute: Index root (0x90).
  #
  # NOTE: Always resident.
  #
  # This is followed by a sequence of index entries (INDEX_ENTRY structures)
  # as described by the index header.
  #
  # When a directory is small enough to fit inside the index root then this
  # is the only attribute describing the directory. When the directory is too
  # large to fit in the index root, on the other hand, two additional attributes
  # are present: an index allocation attribute, containing sub-nodes of the B+
  # directory tree (see below), and a bitmap attribute, describing which virtual
  # cluster numbers (vcns) in the index allocation attribute are in use by an
  # index block.
  #
  # NOTE: The root directory (FILE_root) contains an entry for itself. Other
  # directories do not contain entries for themselves, though.
  #

  ATTRIB_INDEX_ROOT = BinaryStruct.new([
    'L',  'type',                     # Type of the indexed attribute. Is FILE_NAME for directories, zero
    # for view indexes. No other values allowed.
    'L',  'collation_rule',           # Collation rule used to sort the index entries. If type is $FILE_NAME,
    # this must be COLLATION_FILE_NAME
    'L',  'index_block_size',         # Size of index block in bytes (in the index allocation attribute)
    'C',  'clusters_per_index_block', # Size of index block in clusters (in the index allocation attribute),
    # when an index block is >= than a cluster, otherwise sectors per index block
    'a3', nil,                        # Reserved/align to 8-byte boundary
  ])
  # Here follows a node header.
  SIZEOF_ATTRIB_INDEX_ROOT = ATTRIB_INDEX_ROOT.size

  class IndexRoot
    CT_BINARY   = 0x00000000  # Binary compare, MSB is first (does that mean big endian?)
    CT_FILENAME = 0x00000001  # UNICODE strings.
    CT_UNICODE  = 0x00000002  # UNICODE, upper case first.
    CT_ULONG    = 0x00000010  # Standard ULONG, 32-bits little endian.
    CT_SID      = 0x00000011  # Security identifier.
    CT_SECHASH  = 0x00000012  # First security hash, then security identifier.
    CT_ULONGS   = 0x00000013  # Set of ULONGS? (doc is unclear - indicates GUID).

    def self.from_header(header, buf, bs)
      return IndexRoot.new(buf, bs) if header.file_name_indices?
      nil
    end

    attr_reader :type, :nodeHeader, :index, :indexAlloc

    def initialize(buf, boot_sector)
      raise "nil buffer"        if buf.nil?
      raise "nil boot sector"   if boot_sector.nil?

      buf                = buf.read(buf.length) if buf.kind_of?(DataRun)
      @air               = ATTRIB_INDEX_ROOT.decode(buf)
      buf                = buf[SIZEOF_ATTRIB_INDEX_ROOT..-1]

      # Get accessor data.
      @type              = @air['type']
      @collation_rule    = @air['collation_rule']
      @byteSize          = @air['index_block_size']
      @clusterSize       = @air['size_of_index_clus']

      @boot_sector       = boot_sector

      # Get node header & index.
      @foundEntries      = {}
      @indexNodeHeader   = IndexNodeHeader.new(buf)
      @indexEntries      = clean_alloc_entries(DirectoryIndexNode.nodeFactory(buf[@indexNodeHeader.start_entries..-1]))
      @indexAlloc        = {}

      @indexEntries.each { |ie| ie.resolve(boot_sector) }
    end

    def fs
      @boot_sector.fs
    end

    def close
    end

    def to_s
      @type.to_s
    end

    def allocations=(indexAllocations)
      @indexAllocRuns = []
      if @indexNodeHeader.children? && indexAllocations
        indexAllocations.each { |alloc| @indexAllocRuns << [alloc.header, alloc.data_run] }
      end
      @indexAllocRuns
    end

    def bitmap=(bmp)
      if @indexNodeHeader.children?
        @bitmap = bmp.data.unpack("b#{bmp.length * 8}") unless bmp.nil?
      end

      @bitmap
    end

    # Find a name in this index.
    def find(name)
      name = name.downcase
      if @foundEntries.key?(name)
        return @foundEntries[name]
      end

      found = find_in_entries(name, @indexEntries)
      if found.nil?
        # Fallback to full directory search if not found
        found = find_backup(name)
      end
      found
    end

    # Return all names in this index as a sorted string array.
    def glob_names
      @globNames = glob_entries.collect { |e| e.namespace == VirtFS::NTFS::FileName::NS_DOS ? nil : e.name.downcase }.compact if @globNames.nil?
      @globNames
    end

    def find_in_entries(name, entries)
      if @foundEntries.key?(name)
        return @foundEntries[name]
      end

      # TODO: Uses linear search within an index entry; switch to more performant search eventually
      entries.each do |e|
        if e.last? || name < e.name.downcase
          return e.child? ? find_in_entries(name, index_alloc_entries(e.child)) : nil
        end
      end
      nil
    end

    def find_backup(name)
      glob_entries_by_name[name]
    end

    def index_alloc_entries(vcn)
      unless @indexAlloc.key?(vcn)
        begin
          raise "not allocated"    if @bitmap[vcn, 1] == "0"
          header, run = @indexAllocRuns.detect { |h, _r| vcn >= h.specific['first_vcn'] && vcn <= h.specific['last_vcn'] }
          raise "header not found" if header.nil?
          raise "run not found"    if run.nil?

          run.seek_to_vcn(vcn - header.specific['first_vcn'])
          buf = run.read(@byteSize)

          raise "buffer not found" if buf.nil?
          raise "buffer signature is expected to be INDX, but is [#{buf[0, 4].inspect}]" if buf[0, 4] != "INDX"
          irh = IndexRecordHeader.new(buf, @boot_sector.bytes_per_sector)
          buf = irh.data[IndexRecordHeader.size..-1]
          inh = IndexNodeHeader.new(buf)
          @indexAlloc[vcn] = clean_alloc_entries(DirectoryIndexNode.nodeFactory(buf[inh.start_entries..-1]))
          @indexAlloc[vcn].each { |ie| ie.resolve(@boot_sector) }
        rescue => err
          @indexAlloc[vcn] = []
        end
      end

      @indexAlloc[vcn]
    end

    def clean_alloc_entries(entries)
      clean = []
      entries.each do |e|
        if e.last? || !(e.content_len == 0 || (e.ref_mft[1] < 12 && e.name[0, 1] == "$"))
          clean << e
          # Since we are already looping through all entries to clean
          #   them we can store them in a lookup for optimization
          @foundEntries[e.name.downcase] = e unless e.last?
        end
      end
      clean
    end

    def glob_entries
      return @glob_entries unless @glob_entries.nil?

      # Since we are reading all entries, retrieve all of the data in one call
      @indexAllocRuns.each do |_h, r|
        r.rewind
        r.read(r.length)
      end

      @glob_entries = glob_all_entries(@indexEntries)
    end

    def glob_entries_by_name
      if @globbedEntriesByName
        return @foundEntries
      end

      glob_entries.each do |e|
        @foundEntries[e.name.downcase] = e
      end
      @globbedEntriesByName = true
      @foundEntries
    end

    def glob_all_entries(entries)
      ret = []
      entries.each do |e|
        ret += glob_all_entries(index_alloc_entries(e.child)) if e.child?
        ret << e unless e.last?
      end
      ret
    end
  end # class IndexRoot
end # module VirtFS::NTFS
