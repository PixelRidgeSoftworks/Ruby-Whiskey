# frozen_string_literal: true

require_relative '../gems/whiskey-core/lib/whiskey/core/version'

Gem::Specification.new do |spec|
  spec.name          = 'ruby_whiskey'
  spec.version       = Whiskey::Core::VERSION
  spec.authors       = ['Ruby Whiskey Team']
  spec.email         = ['team@rubywhiskey.dev']

  spec.summary       = 'Ruby Whiskey - A web framework to compete with Rails'
  spec.description   = 'Ruby Whiskey is a complete web framework that provides all the tools needed to build modern web applications. This meta-gem installs all Ruby Whiskey components including Core, ORM, Vintages (migrations), Web layer, and CLI tools.'
  spec.homepage      = 'https://github.com/PixelRidgeSoftworks/Ruby-Whiskey'
  spec.license       = 'AGPL-3.0'

  spec.required_ruby_version = '>= 2.7.0'

  spec.files = Dir['lib/**/*', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']

  # Include all whiskey components
  spec.add_dependency 'whiskey-core', Whiskey::Core::VERSION
  spec.add_dependency 'whiskey-orm', Whiskey::Core::VERSION
  spec.add_dependency 'whiskey-vintages', Whiskey::Core::VERSION
  spec.add_dependency 'whiskey-web', Whiskey::Core::VERSION
  spec.add_dependency 'whiskey-cli', Whiskey::Core::VERSION

  spec.add_development_dependency 'rspec', '~> 3.0'
end
