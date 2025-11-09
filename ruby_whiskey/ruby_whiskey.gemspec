# frozen_string_literal: true

require_relative '../gems/whiskey-core/lib/whiskey/core/version'

Gem::Specification.new do |spec|
  spec.name          = 'ruby_whiskey'
  spec.version       = Whiskey::Core::VERSION
  spec.authors       = ['PixelRidge Softworks']
  spec.email         = ['contact@pixelridgesoftworks.com']

  spec.summary       = 'Ruby Whiskey – A modular, developer-friendly Ruby web framework'
  spec.description   = <<~DESC
    Ruby Whiskey is a modern, modular Ruby web framework designed to provide the productivity 
    of Rails without the complexity. This meta-gem installs all Ruby Whiskey components, 
    including Core utilities, the Glass & Cask ORM, Vintages (migrations), Web layer, and CLI tools.
  DESC

  spec.homepage      = 'https://github.com/PixelRidgeSoftworks/Ruby-Whiskey'
  spec.license       = 'AGPL-3.0'
  spec.required_ruby_version = '>= 3.4'

  spec.files = Dir['lib/**/*', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']

  # Meta-gem depends on all components
  spec.add_dependency 'whiskey-core', Whiskey::Core::VERSION
  spec.add_dependency 'whiskey-orm', Whiskey::Core::VERSION
  spec.add_dependency 'whiskey-vintages', Whiskey::Core::VERSION
  spec.add_dependency 'whiskey-web', Whiskey::Core::VERSION
  spec.add_dependency 'whiskey-cli', Whiskey::Core::VERSION

  spec.add_development_dependency 'rspec', '~> 3.0'
end
