require 'ostruct'
require 'virtfs/block_io'
require 'virt_disk'

FactoryGirl.define do
  factory :ntfs, class: OpenStruct do
    recording_path "spec/cassettes/template.yml"

    mount_point "/mnt"

    recording_root { "spec/virtual/" }

    recorder {
      r = VirtFS::CamcorderFS::FS.new(recording_path)
      r.root = recording_root
      r
    }

    path { "#{recording_root}/ntfs1.img" }

    root_dir ["d1", "foo", "bar"]

    glob_dir ["d1/baz", "d1/fle.ext"]

    boot_size 88
  end
end
