module VirtFS::NTFS
  class FS
    # Default index cache size
    DEF_CACHE_SIZE = 50

    attr_accessor :mount_point, :superblock, :root_dir, :index_cache, :cache_hits

    attr_accessor :boot_sector

    def self.match?(blk_device)
      begin
        blk_device.seek(3)
        oem = blk_device.read(8).unpack('a8')[0].strip
        return oem == 'NTFS'
      rescue => err
        return false
      end
    end

    def initialize(blk_device)
      blk_device.seek(0, IO::SEEK_SET)
      @boot_sector = BootSect.new(blk_device, self)
      @boot_sector.setup

      @drive_root  = @boot_sector.root_dir

      # Init cache.
      @index_cache = LruHash.new(DEF_CACHE_SIZE)
      @cache_hits  = 0
    end

    def unnormalize_path(p)
      p[1] == 58 ? p[2, p.size] : p
    end

    def thin_interface?
      true
    end

    def umount
      @mount_point = nil
    end
  end # class FS
end # module VirtFS::Ext3
