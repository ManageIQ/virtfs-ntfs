module VirtFS::NTFS
  class File
    def initialize(dir_entry, boot_sector)
      @bs = boot_sector
      @de = dir_entry
    end

    def to_h
      { :directory? => @de.dir?,
        :file?      => @de.file?,
        :symlink?   => @de.symlink? }
    end

    def fs
      @de.fs
    end

    def size
      @de.length
    end

    def close
    end

    def atime
      @de.afn.aTime
    end

    def ctime
      @de.afn.cTime
    end

    def mtime
      @de.afn.mTime
    end
  end # class File
end # module VirtFS::NTFS
