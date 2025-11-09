# frozen_string_literal: true

require_relative 'orm/version'
require_relative 'orm/core'

module Whiskey
  module ORM
    # Configuration for enabling optional modules
    class << self
      attr_accessor :config
    end

    self.config = {
      validations: false,
      associations: false,
      query: false,
      serialization: false,
      callbacks: false,
      persistence: false
    }

    # Enable specific ORM modules
    def self.enable(module_name)
      case module_name.to_sym
      when :validations
        require_relative 'orm/validations'
        config[:validations] = true
      when :associations
        require_relative 'orm/associations'
        config[:associations] = true
      when :query
        require_relative 'orm/query'
        config[:query] = true
      when :serialization
        require_relative 'orm/serialization'
        config[:serialization] = true
      when :callbacks
        require_relative 'orm/callbacks'
        config[:callbacks] = true
      when :persistence
        require_relative 'orm/persistence'
        config[:persistence] = true
      else
        raise ArgumentError, "Unknown ORM module: #{module_name}"
      end
    end

    # Check if a module is enabled
    def self.enabled?(module_name)
      config[module_name.to_sym] || false
    end

    # Configure ORM with a block
    def self.configure
      yield(config) if block_given?
    end
  end
end
