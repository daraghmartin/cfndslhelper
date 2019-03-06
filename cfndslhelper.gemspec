# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cfndslhelper/version'

Gem::Specification.new do |spec|
  spec.name          = 'cfndslhelper'
  spec.version       = CfnDSLHelper::VERSION
  spec.authors       = ['Daragh Martin']
  spec.email         = ["daragh.martin@gmail.com"]

  spec.summary       = %q{Helper to provide functionality for developing with cfndsl}
  spec.description   = %q{Write a longer description or delete this line.}
  spec.homepage      = 'https://github.com/daraghmartin/cfndslhelper'
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "bin"
  #spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.executables << 'cfndslhelper'
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.13'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_runtime_dependency 'aws-sdk'
  spec.add_runtime_dependency 'cfndsl'
end
