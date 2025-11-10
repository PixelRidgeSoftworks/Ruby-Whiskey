# frozen_string_literal: true

##
# Ruby Whiskey Framework - Environment Management
#
# Provides environment awareness and validation for the Ruby Whiskey framework.
# Handles environment detection, validation, and utility predicates with
# comprehensive error handling for invalid environments.
#
# @author PixelRidge Softworks
# @version 2.0.0
# @since 1.0.0

module Whiskey
  module Core
    # Valid Ruby Whiskey environments
    ENVIRONMENTS = %w[development test production].freeze

    # Custom error for invalid environment
    class InvalidEnvironmentError < StandardError; end
  end

  # Add environment awareness with validation
  class << self
    # Initialize thread-safe environment caching
    @env_mutex = Mutex.new
    @cached_env = nil
    @cached_root_path = nil

    # Get current Ruby Whiskey environment with memoization
    # Caches the environment lookup to avoid repeated ENV access
    # @return [String] the current environment
    def env
      # Fast path - return cached value if available
      return @cached_env if @cached_env

      # Cache miss - resolve and cache with thread safety
      @env_mutex.synchronize do
        @cached_env ||= ENV['WHISKEY_ENV'] || 'development'
      end
    end

    # Set Ruby Whiskey environment with validation
    # Clears cached environment to force re-evaluation
    # @param environment [String, Symbol] the environment to set
    # @raise [InvalidEnvironmentError] if environment is not valid
    def env=(environment)
      env_str = environment.to_s

      unless Core::ENVIRONMENTS.include?(env_str)
        raise Core::InvalidEnvironmentError,
              "Invalid environment: #{env_str}. Valid environments: #{Core::ENVIRONMENTS.join(', ')}"
      end

      # Set environment and clear cache to force re-evaluation
      @env_mutex.synchronize do
        ENV['WHISKEY_ENV'] = env_str
        @cached_env = nil # Clear cache to force fresh lookup
      end
    end

    # Reset cached environment - clears memoized environment lookup
    # Used during testing and environment changes to ensure fresh lookup
    # @return [void]
    def reset_env!
      @env_mutex.synchronize do
        @cached_env = nil
        @cached_root_path = nil
      end
    end

    # Get application root path with memoization
    # Resolves to ENV["WHISKEY_ROOT"] or Dir.pwd if not set
    # @return [String] the application root path
    def root_path
      # Fast path - return cached value if available
      return @cached_root_path if @cached_root_path

      # Cache miss - resolve and cache with thread safety
      @env_mutex.synchronize do
        @cached_root_path ||= ENV['WHISKEY_ROOT'] || Dir.pwd
      end
    end

    # Check if an environment is valid
    # @param environment [String, Symbol] the environment to check
    # @return [Boolean] true if environment is valid
    def env_valid?(environment)
      Core::ENVIRONMENTS.include?(environment.to_s)
    end

    # Check if we're in development environment
    # @return [Boolean] true if in development
    def development?
      env == 'development'
    end

    # Check if we're in production environment
    # @return [Boolean] true if in production
    def production?
      env == 'production'
    end

    # Check if we're in test environment
    # @return [Boolean] true if in test
    def test?
      env == 'test'
    end

    # Validate current environment - ensures env is valid for framework operations
    # @return [String] the current environment if valid
    # @raise [Core::InvalidEnvironmentError] if environment is not in Core::ENVIRONMENTS
    def env!
      current_env = env
      unless Core::ENVIRONMENTS.include?(current_env)
        raise Core::InvalidEnvironmentError,
              "Invalid environment: #{current_env}. Valid environments: #{Core::ENVIRONMENTS.join(', ')}"
      end
      current_env
    end

    # Get environment as symbol - returns :unknown if invalid
    # @return [Symbol] environment as symbol, or :unknown for invalid environments
    def env_symbol
      current_env = env
      Core::ENVIRONMENTS.include?(current_env) ? current_env.to_sym : :unknown
    end

    # Ensure framework is booted - raises error if not booted (safe boot check)
    # Won't raise if Bootloader isn't loaded yet, making it safe to call early
    # @return [Boolean] true if framework is booted
    # @raise [Core::Bootloader::BootError] if framework is not booted
    def ensure_booted!
      # Safe boot check - return true if bootloader methods aren't available yet
      return true unless respond_to?(:booted?) && respond_to?(:boot_error)

      raise boot_error, 'Framework not booted' unless booted?

      true
    end
  end
end
