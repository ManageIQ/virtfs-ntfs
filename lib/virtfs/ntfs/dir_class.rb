require 'active_support/core_ext/object/try' # until we can use the safe nav operator

module VirtFS::NTFS
  class FS
    def dir_delete(p)
      raise "writes not supported"
    end

    def dir_entries(p)
      dir = get_dir(p)
      return nil if dir.nil?
      dir.glob_names
    end

    def dir_exist?(p)
      begin
        !get_dir(p).nil?
      rescue
        false
      end
    end

    def dir_foreach(p, &block)
      r = get_dir(p).try(:glob_names).try(:each, &block)
      block.nil? ? r : nil
    end

    def dir_mkdir(p, permissions)
      raise "writes not supported"
    end

    def dir_new(fs_rel_path, hash_args={}, _open_path=nil, _cwd=nil)
      get_dir(fs_rel_path)
    end

    private

    def get_dir(p)
      p = unnormalize_path(p).downcase

      # Get an array of directory names, kill off the first (it's always empty).
      names = p.split(/[\\\/]/)
      names.shift

      # Get the index for this directory
      get_index(names, p)
    end

    def get_index(names, p)
      return boot_sector.root_dir if names.empty?

      fname = names.join('/')
      if self.index_cache.key?(fname)
        self.cache_hits += 1
        return self.index_cache[fname]
      end

      name = names.pop
      index = get_index(names, p)
      raise "Can't find index: '#{p}'" if index.nil?

      din = index.find(name)
      raise "Can't find index: '#{p}'" if din.nil?

      index = din.resolve(boot_sector).index_root
      raise "Can't find index: '#{p}'" if index.nil?

      self.index_cache[fname] = index
    end
  end
end
