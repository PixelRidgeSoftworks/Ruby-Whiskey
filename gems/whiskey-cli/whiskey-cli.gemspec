# frozen_string_literal: true

require_relative '../../whiskey-core/lib/whiskey/core/version'

Gem::Specification.new do |spec|
  spec.name          = 'whiskey-cli'
  spec.version       = Whiskey::Core::VERSION
  spec.authors       = ['PixelRidge Softworks']
  spec.email         = ['contact@pixelridgesoftworks.com']

  spec.summary       = 'Bartender CLI - Command-line tools for Ruby Whiskey'
  spec.description   = <<~DESC
    The Bartender CLI provides command-line tools to scaffold applications, run servers, 
    manage Vintages (migrations), and interact with the Whiskey ORM. Fully optional and modular.
  DESC

  spec.homepage      = 'https://github.com/PixelRidgeSoftworks/Ruby-Whiskey'
  spec.license       = 'AGPL-3.0'
  spec.required_ruby_version = '>= 3.4'

  spec.files = Dir['lib/**/*', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']
  spec.bindir = 'bin'
  spec.executables = ['bartender']

  # CLI only depends on core
  spec.add_dependency 'whiskey-core', Whiskey::Core::VERSION

  spec.add_development_dependency 'rspec', '~> 3.0'
end
