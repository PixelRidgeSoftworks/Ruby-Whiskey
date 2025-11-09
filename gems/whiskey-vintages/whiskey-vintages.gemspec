# frozen_string_literal: true

require_relative '../../whiskey-core/lib/whiskey/core/version'

Gem::Specification.new do |spec|
  spec.name          = 'whiskey-vintages'
  spec.version       = Whiskey::Core::VERSION
  spec.authors       = ['Ruby Whiskey Team']
  spec.email         = ['team@rubywhiskey.dev']

  spec.summary       = 'Database migrations for Ruby Whiskey framework'
  spec.description   = 'Provides Vintage and Cellar components for database migrations in the Ruby Whiskey web framework'
  spec.homepage      = 'https://github.com/PixelRidgeSoftworks/Ruby-Whiskey'
  spec.license       = 'AGPL-3.0'

  spec.required_ruby_version = '>= 2.7.0'

  spec.files = Dir['lib/**/*', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']

  spec.add_dependency 'whiskey-core', Whiskey::Core::VERSION
  spec.add_dependency 'whiskey-orm', Whiskey::Core::VERSION

  spec.add_development_dependency 'rspec', '~> 3.0'
end
