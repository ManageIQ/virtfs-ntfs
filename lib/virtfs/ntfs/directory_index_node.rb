require 'binary_struct'
require 'virtfs/ntfs/attributes/file_name'
require 'virtfs/ntfs/utils'

module VirtFS::NTFS
  DIR_INDEX_NODE = BinaryStruct.new([
    'Q',  'mft_ref',          # MFT file reference for file name (goofy ref).
    'S',  'length',           # Length of entry.
    'S',  'content_len',      # Length of $FILE_NAME attrib
    'L',  'flags',            # See IN_ below (note: these will eventually become general flags)
  ])
  # Here follows a $FILE_NAME attribute if content_len > 0.
  # Last 8 bytes starting on 8 byte boundary are the VCN of the child node in $INDEX_ALLOCATION (if IN_HAS_CHILD is set).
  SIZEOF_DIR_INDEX_NODE = DIR_INDEX_NODE.size

  class DirectoryIndexNode
    IN_HAS_CHILD   = 0x00000001
    IN_LAST_ENTRY  = 0x00000002

    attr_reader :ref_mft, :length, :content_len, :flags, :child, :afn, :mft_entry

    def self.nodeFactory(buf)
      nodes = []
      loop do
        node   = DirectoryIndexNode.new(buf)
        buf    = buf[node.length..-1]
        nodes << node
        break if node.last?
      end

      nodes
    end

    def initialize(buf)
      raise "nil buffer" if buf.nil?

      buf = buf.read(buf.length) if buf.kind_of?(DataRun)
      # Decode the directory index node structure.
      @din = DIR_INDEX_NODE.decode(buf)

      # Get accessor data.
      @mft_entry   = nil
      @ref_mft     = VirtFS::NTFS::Utils.mk_ref(@din['mft_ref'])
      @length      = @din['length']
      @content_len = @din['content_len']
      @flags       = @din['flags']

      # If there's a $FILE_NAME attrib get it.
      @afn = FileName.new(buf[SIZEOF_DIR_INDEX_NODE, buf.size]) if @content_len > 0

      # If there's a child node VCN get it.
      if child?
        # Child node VCN is located 8 bytes before 'length' bytes.
        # NOTE: If the node has 0 contents, it's offset 16.
        @child = buf[@content_len == 0 ? 16 : @length - 8, 8].unpack('Q')[0]
        if @child.class == Bignum #|| Fixnum?
          # buf.hex_dump(:obj => STDOUT, :meth => :puts, :newline => false)
          raise "MIQ(NTFS::DirectoryIndexNode.initialize) Bad child node: #{@child}"
        end
      end
    end

    # String rep.
    def to_s
      "\#<#{self.class}:0x#{'%08x' % object_id} name='#{name}'>"
    end

    # Return file name (if resolved).
    def name
      @afn.nil? ? nil : @afn.name
    end

    # Return namespace.
    def namespace
      @afn.nil? ? nil : @afn.namespace
    end

    # Return true if has children.
    def child?
      VirtFS::NTFS::Utils.bit?(@flags, IN_HAS_CHILD)
    end

    # Return true if this is the last entry.
    def last?
      VirtFS::NTFS::Utils.bit?(@flags, IN_LAST_ENTRY)
    end

    # If content is 0, then obviously not a directory.
    def dir?
      return false if @content_len == 0
      @mft_entry.dir?
    end

    def file?
      return !dir?
    end

    def symlink?
      false
    end

    # Resolves this node's file reference.
    def resolve(bs)
      if @content_len > 0
        @mft_entry = bs.mft_entry(@ref_mft[1])
        #raise "MIQ(NTFS::DirectoryIndexNode.resolve) Stale reference: #{inspect}" if @ref_mft[0] != @mft_entry.sequence_num
      end
      @mft_entry
    end
  end # class DirectoryIndexNode
end # module VirtFS::NTFS
