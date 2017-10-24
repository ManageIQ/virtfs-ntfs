require 'ostruct'
require 'virtfs/block_io'
require 'virt_disk'

FactoryGirl.define do
  factory :ntfs, class: OpenStruct do
    path File.expand_path('images/ntfs1.img')
    fs { VirtFS::NTFS::FS.new(VirtDisk::Disk.new(VirtDisk::FileIo.new(path))) }
    root_dir ["d1", "foo", "bar"]
    glob_dir ["d1/baz", "d1/fle.ext"]
    boot_size 88
  end
end
