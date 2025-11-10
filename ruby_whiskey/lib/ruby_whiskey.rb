# frozen_string_literal: true

# Ruby Whiskey - Meta-gem that installs all components

require 'whiskey/core/version'
require 'whiskey/core/config'
require 'whiskey/core/logger'
require 'whiskey/core/bootloader'

require 'whiskey/orm'

require 'whiskey/vintages/vintage'
require 'whiskey/vintages/cellar'

require 'whiskey/web/router'
require 'whiskey/web/server'

require 'whiskey/cli/bartender'

module RubyWhiskey
  VERSION = Whiskey::Core::VERSION

  # Main entry point for Ruby Whiskey framework
  def self.version
    VERSION
  end
end
