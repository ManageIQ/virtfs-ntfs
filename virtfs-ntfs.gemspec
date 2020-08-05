# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'virtfs/ntfs/version'

Gem::Specification.new do |spec|
  spec.name          = "virtfs-ntfs"
  spec.version       = VirtFS::NTFS::VERSION
  spec.authors       = ["ManageIQ Developers"]

  spec.summary       = %q{An NTFS based filesystem module for VirtFS}
  spec.description   = %q{An NTFS based filesystem module for VirtFS}
  spec.homepage      = "https://github.com/ManageIQ/virtfs-ntfs"
  spec.license       = "Apache 2.0"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "uuidtools", "~> 2.2"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.0"
end
