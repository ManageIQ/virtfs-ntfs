require 'binary_struct'

module VirtFS::NTFS
  class AttribData
    #
    # DATA_ATTR - Attribute: Data attribute (0x80)
    #
    # NOTE: Can be resident or non-resident.
    #
    # Data contents of a file (i.e. the unnamed stream) or of a named stream.
    #
    def self.from_header(header, buf)
      header.namelen == 0 ? AttribData.new(buf) : nil
    end

    attr_reader :data, :length, :run

    def initialize(buf)
      @run    = buf if buf.kind_of?(VirtFS::NTFS::DataRun)
      @data   = buf
      @length = @data.length
      @pos    = 0
    end

    def to_s
      return @data.hex_dump if @data.kind_of?(String)

      raise "MIQ(NTFS::AttribData.to_s) Unexpected data class: #{@data.class}" unless @data.kind_of?(NTFS::DataRun)

      # Must be a Data Run
      savedPos = @pos
      seek(0)
      data = read(@length)
      seek(savedPos)
      data
    end

    # This now behaves exactly like a normal read.
    def read(bytes = @length)
      return nil if @pos >= @length
      bytes = @length - @pos if bytes.nil?
      bytes = @length - @pos if @pos + bytes > @length

      out = @data[@pos, bytes]      if @data.kind_of?(String)
      out = @data.read(bytes)       if @data.kind_of?(NTFS::DataRun)

      @pos += out.size
      out
    end

    def seek(offset, method = IO::SEEK_SET)
      @pos = case method
             when IO::SEEK_CUR then (@pos + offset)
             when IO::SEEK_END then (@length - offset)
             when IO::SEEK_SET then offset
             end
      @data.seek(offset, method) if @data.kind_of?(NTFS::DataRun)
      @pos
    end

    def rewind
      seek(0)
    end
  end
end # module NTFS
