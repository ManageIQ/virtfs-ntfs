require 'spec_helper'

describe VirtFS::NTFS do
  def cassette_path
    "spec/cassettes/ntfs.yml"
  end

  it 'has a version number' do
    expect(VirtFS::NTFS::VERSION).not_to be nil
  end
end
