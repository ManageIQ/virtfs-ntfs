module VirtFS::NTFS
  class IndexAllocation
    def self.from_header(header, buf)
      return IndexAllocation.new(buf, header) if header.file_name_indices?
      nil
    end

    attr_reader :data_run, :header

    def initialize(buf, header)
      raise "Buffer must be DataRun (passed #{buf.class.name})"          unless buf.kind_of?(DataRun)
      raise "Header must be AttribHeader (passed #{header.class.name})"  unless header.kind_of?(VirtFS::NTFS::AttribHeader)

      @data_run = buf
      @header   = header
    end
  end
end
