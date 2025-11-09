# frozen_string_literal: true

require_relative '../../whiskey-core/lib/whiskey/core/version'

Gem::Specification.new do |spec|
  spec.name          = 'whiskey-orm'
  spec.version       = Whiskey::Core::VERSION
  spec.authors       = ['PixelRidge Softworks']
  spec.email         = ['contact@pixelridgesoftworks.com']

  spec.summary       = 'Glass & Cask ORM for Ruby Whiskey'
  spec.description   = <<~DESC
    Provides the Whiskey ORM system: create Glass objects, fill them with SQL, manipulate them, 
    and persist to the database using `drink`. Fully modular and flexible, with validations 
    and object transformations.
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
