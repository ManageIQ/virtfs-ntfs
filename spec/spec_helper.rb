require 'simplecov'
SimpleCov.start

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'virtfs'
require 'virtfs/ntfs'
require 'virtfs-nativefs-thick'
require 'factory_girl'

# XXX bug in camcorder (missing dependency)
require 'fileutils'
require 'virtfs-camcorderfs'

require 'virt_disk'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
  end

  config.include FactoryGirl::Syntax::Methods

  config.before(:suite) do
    FactoryGirl.find_definitions
  end

  config.before(:all) do
    VirtFS.mount(VirtFS::NativeFS::Thick.new, "/")

    @orig_dir = Dir.pwd
    @ntfs = build(:ntfs,
                  recording_path: cassette_path)

    VirtFS.mount(@ntfs.recorder, File.expand_path("#{@ntfs.recording_root}"))
    VirtFS.activate!
    VirtFS.dir_chdir(@orig_dir)

    @root     = @ntfs.mount_point
    block_dev = VirtDisk::Disk.new(VirtDisk::FileIo.new(@ntfs.path))
    ntfs      = VirtFS::NTFS::FS.new(block_dev)
    VirtFS.mount(ntfs, @ntfs.mount_point)
  end

  config.after(:all) do
    VirtFS.deactivate!
    VirtFS.umount(@ntfs.mount_point)
    VirtFS.dir_chdir("/")
    VirtFS.umount(File.expand_path("#{@ntfs.recording_root}"))
    VirtFS.umount("/")
  end
end

def reset_context
  VirtFS.context_manager.reset_all
end
