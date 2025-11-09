# frozen_string_literal: true

require_relative '../../whiskey-core/lib/whiskey/core/version'

Gem::Specification.new do |spec|
  spec.name          = 'whiskey-web'
  spec.version       = Whiskey::Core::VERSION
  spec.authors       = ['PixelRidge Softworks']
  spec.email         = ['contact@pixelridgesoftworks.com']

  spec.summary       = 'Web layer for Ruby Whiskey – routing & rendering'
  spec.description   = <<~DESC
    Provides routing, controllers, and rendering for Ruby Whiskey applications. 
    Fully modular and can be used independently of other Whiskey components.
  DESC

  spec.homepage      = 'https://github.com/PixelRidgeSoftworks/Ruby-Whiskey'
  spec.license       = 'AGPL-3.0'
  spec.required_ruby_version = '>= 3.4'

  spec.files = Dir['lib/**/*', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']

  # Only depends on core utilities
  spec.add_dependency 'whiskey-core', Whiskey::Core::VERSION

  spec.add_development_dependency 'rspec', '~> 3.0'
end
