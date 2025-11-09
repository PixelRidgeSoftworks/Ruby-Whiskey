# frozen_string_literal: true

require_relative 'lib/whiskey/core/version'

Gem::Specification.new do |spec|
  spec.name          = 'whiskey-core'
  spec.version       = Whiskey::Core::VERSION
  spec.authors       = ['PixelRidge Softworks']
  spec.email         = ['contact@pixelridgesoftworks.com']

  spec.summary       = 'Core utilities for Ruby Whiskey framework'
  spec.description   = 'Provides essential utilities, configuration, and shared classes for all Ruby Whiskey components.'
  spec.homepage      = 'https://github.com/PixelRidgeSoftworks/Ruby-Whiskey'
  spec.license       = 'AGPL-3.0'
  spec.required_ruby_version = '>= 3.4'

  spec.files = Dir['lib/**/*', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']

  spec.add_development_dependency 'rspec', '~> 3.0'
end
