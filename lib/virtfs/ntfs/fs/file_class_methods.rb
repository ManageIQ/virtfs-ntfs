module VirtFS::NTFS
  class FS
    def file_atime(p)
      file = get_file(p)
      raise Errno::ENOENT, "No such file or directory" if file.nil?
      file.afn.aTime
    end

    def file_blockdev?(p)
    end

    def file_chardev?(p)
    end

    def file_chmod(permission, p)
      raise "writes not supported"
    end

    def file_chown(owner, group, p)
      raise "writes not supported"
    end

    def file_ctime(p)
      file = get_file(p)
      raise Errno::ENOENT, "No such file or directory" if file.nil?
      file.afn.cTime
    end

    def file_delete(p)
      raise "writes not supported"
    end

    def file_directory?(p)
      file = get_file(p)
      return false if file.nil?
      file.resolve(boot_sector)
      return true if file.dir?
      false
    end

    def file_executable?(p)
    end

    def file_executable_real?(p)
    end

    def file_exist?(p)
      !get_file(p).nil?
    end

    def file_file?(p)
      file = get_file(p)
      return false if file.nil?
      file.resolve(boot_sector)
      return false if file.dir?
      true
    end

    def file_ftype(p)
    end

    def file_grpowned?(p)
    end

    def file_identical?(p1, p2)
    end

    def file_lchmod(permission, p)
      raise "writes not supported"
    end

    def file_lchown(owner, group, p)
      raise "writes not supported"
    end

    def file_link(p1, p2)
      raise "writes not supported"
    end

    def file_lstat(p)
      file = get_file(p)
      raise Errno::ENOENT, "No such file or directory" if file.nil?
      VirtFS::Stat.new(VirtFS::NTFS::File.new(file, boot_sector).to_h)
    end

    def file_mtime(p)
      file = get_file(p)
      raise Errno::ENOENT, "No such file or directory" if file.nil?
      file.afn.mTime
    end

    def file_owned?(p)
    end

    def file_pipe?(p)
    end

    def file_readable?(p)
    end

    def file_readable_real?(p)
    end

    def file_readlink(p)
    end

    def file_rename(p1, p2)
    end

    def file_setgid?(p)
    end

    def file_setuid?(p)
    end

    def file_size(p)
      file = get_file(p)
      raise Errno::ENOENT, "No such file or directory" if file.nil?
      file.afn.length
    end

    def file_socket?(p)
    end

    def file_stat(p)
    end

    def file_sticky?(p)
    end

    def file_symlink(oname, p)
    end

    def file_symlink?(p)
    end

    def file_truncate(p, len)
    end

    def file_utime(atime, mtime, p)
    end

    def file_world_readable?(p)
    end

    def file_world_writable?(p)
    end

    def file_writable?(p)
    end

    def file_writable_real?(p)
    end

    def file_new(f, parsed_args, _open_path, _cwd)
      de  = get_file(f)
      raise Errno::ENOENT, "No such file or directory" if de.nil?
      File.new(de, boot_sector)
    end

    private

    def get_file(p)
      p = unnormalize_path(p).downcase

      dir = p.split(/[\\\/]/)
      fname = dir[dir.size - 1]
      fname = "." if fname.nil? # Special case: if fname is nil then dir is root.
      dir = dir.size > 2 ? dir[0...dir.size - 1].join('/') : '/'

      # Check for this file in the cache.
      cache_name = "#{dir == '/' ? '' : dir}/#{fname}"
      if index_cache.key?(cache_name)
        self.cache_hits += 1
        return index_cache[cache_name]
      end

      # Look for file in dir, but don't error if it doesn't exist.
      # NOTE: if p is a directory that's ok, find it.
      file = nil
      index = get_dir(dir)
      file = index.find(fname) unless index.nil?

      index_cache[cache_name] = file
    end
  end
end
