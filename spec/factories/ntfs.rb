require 'ostruct'
require 'virtfs/block_io'
require 'virt_disk/block_file'

FactoryGirl.define do
  factory :ntfs, class: OpenStruct do
    path 'ntfs.fs'
    fs { VirtFS::NTFS::FS.new(VirtFS::BlockIO.new(VirtDisk::BlockFile.new(path))) }
    root_dir ["dir1", "dir2", "file1", "file2", "file3", "file4"]
    glob_dir ["dir1/subdir1", "dir1/subdir2"]
    boot_size 2048
  end
end
