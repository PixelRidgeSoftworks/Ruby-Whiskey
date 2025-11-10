# frozen_string_literal: true

##
# Ruby Whiskey Framework - Framework Delegators
#
# Provides framework-wide delegation methods that point to bootloader subsystems,
# lifecycle events, analytics, and other core functionality. Maintains global
# method signatures for backward compatibility while delegating to appropriate
# subsystem implementations.
#
# Organized into logical submodules for improved maintainability and extensibility:
# - Boot: Bootloader and lifecycle management
# - Config: Configuration access and management
# - Subsystems: Subsystem registration and management
# - Diagnostics: Status reporting and introspection
# - Hooks: Boot hook management
#
# ## Thread Safety
#
# Memoized singleton instances (@bootloader_instance, @config_instance) are
# protected by a shared mutex to ensure atomic access across threads. All
# delegation methods are thread-safe.
#
# @author PixelRidge Softworks
# @version 2.0.0
# @since 1.0.0

module Whiskey
  ##
  # Delegator submodules organized by functional area
  # @private
  module Delegators
    # Shared mutex for thread-safe memoization
    # @private
    MUTEX = Mutex.new.freeze

    ##
    # Shared utilities for delegator modules
    # @private
    module Utils
      module_function

      # Safe bootloader method call with respond_to? guard and optional debug logging
      # @param method [Symbol] method to call on bootloader
      # @param args [Array] method arguments
      # @param kwargs [Hash] keyword arguments
      # @param block [Proc] optional block
      # @return [Object, nil] method result or nil if method not available
      # @private
      def safe_bootloader_call(method, *args, **kwargs, &block)
        bootloader = Boot.bootloader_instance

        unless bootloader.respond_to?(method)
          # Debug logging for delegation failures (development only)
          if Whiskey.env == 'development'
            Whiskey::Core::Log.debug("Delegation failed: bootloader does not respond to #{method}")
          end
          return nil
        end

        if kwargs.empty? && block.nil?
          bootloader.send(method, *args)
        elsif block.nil?
          bootloader.send(method, *args, **kwargs)
        elsif kwargs.empty?
          bootloader.send(method, *args, &block)
        else
          bootloader.send(method, *args, **kwargs, &block)
        end
      end
    end

    ##
    # Bootloader and lifecycle management delegators
    # @private
    module Boot
      extend self

      # Get the core bootloader singleton instance with fault-tolerant memoization
      # @return [Whiskey::Core::Bootloader::Core] the bootloader singleton instance
      # @private
      def bootloader_instance
        return @bootloader_instance if @bootloader_instance

        MUTEX.synchronize do
          return @bootloader_instance if @bootloader_instance

          @bootloader_instance = resolve_bootloader_with_retry.freeze
        end
      end

      # Global bootloader for Ruby Whiskey framework
      # @param profile [Symbol, nil] boot profile to use for selective loading
      # @param force_reload [Boolean] whether to reload config if already loaded
      # @param dry_run [Boolean] simulate boot without actual loading
      # @param parallel [Boolean] whether to boot subsystems in parallel
      # @return [Boolean, nil] true if boot sequence completed successfully
      def boot!(profile: nil, force_reload: false, dry_run: false, parallel: false)
        Utils.safe_bootloader_call(:boot!, profile: profile, force_reload: force_reload, dry_run: dry_run,
                                           parallel: parallel)
      end

      # Shutdown the framework gracefully
      # @return [Boolean, nil] true if shutdown completed successfully
      def shutdown!
        Utils.safe_bootloader_call(:shutdown!)
      end

      # Reload the entire framework
      # @return [Boolean, nil] true if successfully reloaded
      def reload!
        Utils.safe_bootloader_call(:reload!)
      end

      # Check if framework has been booted
      # @return [Boolean] true if boot sequence completed
      def booted?
        Utils.safe_bootloader_call(:booted?) || false
      end

      # Get the boot error class
      # @return [Class] the BootError class
      # @private
      def boot_error
        Core::Bootloader::BootError
      end

      # Get the boot context class
      # @return [Class] the BootContext class
      # @private
      def boot_context
        Core::Bootloader::BootContext
      end

      # Get the lifecycle events DSL module
      # @return [Module] the LifecycleEventsDSL module
      # @private
      def lifecycle_events_dsl
        Core::Bootloader::LifecycleEventsDSL
      end

      private

      # Resolve bootloader instance with fault tolerance and retry logic
      # @return [Whiskey::Core::Bootloader::Core] bootloader instance
      # @private
      def resolve_bootloader_with_retry
        attempts = 0
        begin
          Core::Bootloader::Core.instance
        rescue StandardError => e
          attempts += 1
          if attempts <= 1
            # Log warning and retry once
            Whiskey::Core::Log.warn("Bootloader instance resolution failed (attempt #{attempts}): #{e.message}. Retrying...")
            retry
          else
            # Log error and re-raise after retry limit exceeded
            Whiskey::Core::Log.error("Bootloader instance resolution failed after #{attempts} attempts: #{e.message}")
            raise
          end
        end
      end
    end

    ##
    # Configuration access and management delegators
    # @private
    module Config
      extend self

      # Get cached config instance with thread-safe memoization
      # @return [Object] the config cache accessor
      # @private
      def config_instance
        return @config_instance if @config_instance

        MUTEX.synchronize do
          return @config_instance if @config_instance

          @config_instance = resolve_config_instance.freeze
        end
      end

      # Access configuration cache at top level
      # Prefers instance-level config_cache if available; fallback to ConfigCache class
      # Usage: Whiskey.config.get(:orm) or bootloader.config_cache for instance-backed access
      # @return [Object] the config cache accessor
      def config
        config_instance
      end

      # Get configuration value for a subsystem (convenience wrapper)
      # @param key [Symbol] the subsystem name
      # @return [Hash, nil] cached config or nil
      def config_get(key)
        config_inst = config_instance
        config_inst.respond_to?(:get) ? config_inst.get(key) : nil
      end

      # Set configuration value for a subsystem (convenience wrapper)
      # @param key [Symbol] the subsystem name
      # @param value [Hash] the config to cache
      # @return [void]
      def config_set(key, value)
        config_inst = config_instance
        if config_inst.respond_to?(:set)
          config_inst.set(key, value)
        elsif config_inst.respond_to?(:cache_config)
          config_inst.cache_config(key, value)
        end
      end

      private

      # Resolve config instance with safe guards
      # @return [Object] config instance
      # @private
      def resolve_config_instance
        bootloader = Boot.bootloader_instance
        if bootloader.respond_to?(:config_cache)
          bootloader.config_cache
        else
          Core::Bootloader::ConfigCache
        end
      end
    end

    ##
    # Subsystem registration and management delegators
    # @private
    module Subsystems
      module_function

      # Register a subsystem with the global boot system
      # @param name [Symbol] the subsystem name
      # @param subsystem_module [Module] the subsystem module
      # @param priority [Integer] boot priority (default: 50)
      # @param depends_on [Array<Symbol>] subsystem dependencies
      # @return [Boolean, nil] true if successfully registered
      def register_subsystem(name, subsystem_module, priority: 50, depends_on: [])
        Utils.safe_bootloader_call(:register_subsystem, name, subsystem_module, priority: priority,
                                                                                depends_on: depends_on)
      end

      # Unregister a subsystem
      # @param name [Symbol] the subsystem name
      # @return [Boolean, nil] true if successfully unregistered
      def unregister_subsystem(name)
        Utils.safe_bootloader_call(:unregister_subsystem, name)
      end

      # Get list of registered subsystems
      # @return [Array<Symbol>] registered subsystem names
      def registered_subsystems
        Utils.safe_bootloader_call(:registered_subsystems) || [].freeze
      end

      # Get a specific subsystem
      # @param name [Symbol] the subsystem name
      # @return [Module, nil] the subsystem module or nil
      def subsystem(name)
        Utils.safe_bootloader_call(:subsystem, name)
      end

      # Attempt to recover a failed subsystem
      # @param name [Symbol] the subsystem name to recover
      # @return [Boolean, nil] true if recovery successful
      def recover_subsystem(name)
        Utils.safe_bootloader_call(:recover_subsystem, name)
      end
    end

    ##
    # Status reporting and diagnostics delegators
    # @private
    module Diagnostics
      module_function

      # Get framework status summary for quick introspection
      # @param compact [Boolean] if true, omit subsystem details to reduce output size
      # @return [Hash] diagnostic summary with key framework state
      def status_summary(compact: false)
        bootloader = Boot.bootloader_instance
        summary = {
          env: Whiskey.env,
          timestamp: Time.now,
          ruby_version: RUBY_VERSION,
          pid: Process.pid
        }.freeze

        # Build summary with safe respond_to? checks
        summary[:booted] = bootloader.respond_to?(:booted?) ? bootloader.booted? : false
        summary[:boot_time] = bootloader.respond_to?(:boot_duration) ? bootloader.boot_duration : nil
        summary[:error_count] = bootloader.respond_to?(:boot_errors) ? bootloader.boot_errors.size : 0
        summary[:config_loaded] = defined?(Whiskey::Config) &&
                                  Whiskey::Config.respond_to?(:loaded?) &&
                                  Whiskey::Config.loaded?

        # Include detailed subsystem information unless compact mode is enabled
        if compact
          # In compact mode, only include counts
          subsystems = bootloader.respond_to?(:registered_subsystems) ? bootloader.registered_subsystems : [].freeze
          summary[:subsystem_count] = subsystems.size
        else
          summary[:subsystems] =
            bootloader.respond_to?(:registered_subsystems) ? bootloader.registered_subsystems : [].freeze
          summary[:subsystem_count] = summary[:subsystems].size

          summary[:failed_subsystems] = if bootloader.respond_to?(:failed_subsystems)
                                          bootloader.failed_subsystems.keys.freeze
                                        else
                                          [].freeze
                                        end
        end

        summary
      end

      # Get comprehensive boot analytics
      # @return [Hash] structured analytics data
      def analytics
        Utils.safe_bootloader_call(:analytics) || {}.freeze
      end

      # Get boot status information
      # @return [Hash] boot status details
      def boot_status
        Utils.safe_bootloader_call(:boot_status) || {}.freeze
      end

      # Get lightweight diagnostics information
      # @return [Hash] diagnostic summary
      def diagnostics
        Utils.safe_bootloader_call(:diagnostics) || {}.freeze
      end

      # Get detailed boot manifest
      # @return [Hash] detailed information about booted subsystems
      def manifest
        Utils.safe_bootloader_call(:manifest) || {}.freeze
      end
    end

    ##
    # Boot hook management delegators
    # @private
    module Hooks
      module_function

      # Add a custom boot hook (backward compatible)
      # @param phase_or_name [Symbol] hook phase or name (for backward compatibility)
      # @param name_or_callable [Symbol, Proc] hook name or callable (for backward compatibility)
      # @param callable [Proc] the hook to execute
      # @param target [Symbol] optional target subsystem for scoped hooks
      # @param order [Integer] execution order (lower numbers execute first, default: 50)
      # @param block [Block] block form of callable
      # @return [void]
      def add_boot_hook(phase_or_name, name_or_callable = nil, callable = nil, target: nil, order: 50, &block)
        Utils.safe_bootloader_call(:add_boot_hook, phase_or_name, name_or_callable, callable,
                                   target: target, order: order, &block)
      end

      # Remove a boot hook (backward compatible)
      # @param phase_or_name [Symbol] hook phase or name (for backward compatibility)
      # @param name [Symbol] hook name (optional)
      # @return [Boolean, nil] true if hook was removed
      def remove_boot_hook(phase_or_name, name = nil)
        Utils.safe_bootloader_call(:remove_boot_hook, phase_or_name, name)
      end
    end
  end

  ##
  # =============================================================================
  # PUBLIC API - Framework-level delegator methods
  # =============================================================================
  #
  # The following methods constitute the public API for Ruby Whiskey framework.
  # These delegate to the appropriate submodule while maintaining backward
  # compatibility with existing method signatures.
  ##

  class << self
    # Get the core bootloader singleton instance
    # @return [Whiskey::Core::Bootloader::Core] the bootloader singleton instance
    def bootloader
      Delegators::Boot.bootloader_instance
    end

    # Get the logging system
    # @return [Whiskey::Core::Log] the log class
    def log
      Core::Log
    end

    # Get the boot error class
    # @return [Class] the BootError class
    # @private
    def boot_error
      Delegators::Boot.boot_error
    end

    # Get the boot context class
    # @return [Class] the BootContext class
    # @private
    def boot_context
      Delegators::Boot.boot_context
    end

    # Get the lifecycle events DSL module
    # @return [Module] the LifecycleEventsDSL module
    # @private
    def lifecycle_events_dsl
      Delegators::Boot.lifecycle_events_dsl
    end

    # Get framework status summary for quick introspection
    # @param compact [Boolean] if true, omit subsystem details to reduce output size
    # @return [Hash] diagnostic summary with key framework state
    def status_summary(compact: false)
      Delegators::Diagnostics.status_summary(compact: compact)
    end

    # Access configuration cache at top level
    # @return [Object] the config cache accessor
    def config
      Delegators::Config.config
    end

    # Get configuration value for a subsystem (convenience wrapper)
    # @param key [Symbol] the subsystem name
    # @return [Hash, nil] cached config or nil
    def config_get(key)
      Delegators::Config.config_get(key)
    end

    # Set configuration value for a subsystem (convenience wrapper)
    # @param key [Symbol] the subsystem name
    # @param value [Hash] the config to cache
    def config_set(key, value)
      Delegators::Config.config_set(key, value)
    end

    # Global bootloader for Ruby Whiskey framework
    # @param profile [Symbol, nil] boot profile to use for selective loading
    # @param force_reload [Boolean] whether to reload config if already loaded
    # @param dry_run [Boolean] simulate boot without actual loading
    # @param parallel [Boolean] whether to boot subsystems in parallel
    # @return [Boolean] true if boot sequence completed successfully
    def boot!(profile: nil, force_reload: false, dry_run: false, parallel: false)
      Delegators::Boot.boot!(profile: profile, force_reload: force_reload, dry_run: dry_run, parallel: parallel)
    end

    # Shutdown the framework gracefully
    # @return [Boolean] true if shutdown completed successfully
    def shutdown!
      Delegators::Boot.shutdown!
    end

    # Register a subsystem with the global boot system
    # @param name [Symbol] the subsystem name
    # @param subsystem_module [Module] the subsystem module
    # @param priority [Integer] boot priority (default: 50)
    # @param depends_on [Array<Symbol>] subsystem dependencies
    # @return [Boolean] true if successfully registered
    def register_subsystem(name, subsystem_module, priority: 50, depends_on: [])
      Delegators::Subsystems.register_subsystem(name, subsystem_module, priority: priority, depends_on: depends_on)
    end

    # Attempt to recover a failed subsystem
    # @param name [Symbol] the subsystem name to recover
    # @return [Boolean] true if recovery successful
    def recover_subsystem(name)
      Delegators::Subsystems.recover_subsystem(name)
    end

    # Get comprehensive boot analytics
    # @return [Hash] structured analytics data
    def analytics
      Delegators::Diagnostics.analytics
    end

    # Unregister a subsystem
    # @param name [Symbol] the subsystem name
    # @return [Boolean] true if successfully unregistered
    def unregister_subsystem(name)
      Delegators::Subsystems.unregister_subsystem(name)
    end

    # Get list of registered subsystems
    # @return [Array<Symbol>] registered subsystem names
    def registered_subsystems
      Delegators::Subsystems.registered_subsystems
    end

    # Get a specific subsystem
    # @param name [Symbol] the subsystem name
    # @return [Module, nil] the subsystem module or nil
    def subsystem(name)
      Delegators::Subsystems.subsystem(name)
    end

    # Reload the entire framework
    # @return [Boolean] true if successfully reloaded
    def reload!
      Delegators::Boot.reload!
    end

    # Check if framework has been booted
    # @return [Boolean] true if boot sequence completed
    def booted?
      Delegators::Boot.booted?
    end

    # Get boot status information
    # @return [Hash] boot status details
    def boot_status
      Delegators::Diagnostics.boot_status
    end

    # Get lightweight diagnostics information
    # @return [Hash] diagnostic summary
    def diagnostics
      Delegators::Diagnostics.diagnostics
    end

    # Get detailed boot manifest
    # @return [Hash] detailed information about booted subsystems
    def manifest
      Delegators::Diagnostics.manifest
    end

    # Add a custom boot hook (backward compatible)
    # @param phase_or_name [Symbol] hook phase or name (for backward compatibility)
    # @param name_or_callable [Symbol, Proc] hook name or callable (for backward compatibility)
    # @param callable [Proc] the hook to execute
    # @param target [Symbol] optional target subsystem for scoped hooks
    # @param order [Integer] execution order (lower numbers execute first, default: 50)
    # @param block [Block] block form of callable
    def add_boot_hook(phase_or_name, name_or_callable = nil, callable = nil, target: nil, order: 50, &block)
      Delegators::Hooks.add_boot_hook(phase_or_name, name_or_callable, callable, target: target, order: order, &block)
    end

    # Remove a boot hook (backward compatible)
    # @param phase_or_name [Symbol] hook phase or name (for backward compatibility)
    # @param name [Symbol] hook name (optional)
    # @return [Boolean] true if hook was removed
    def remove_boot_hook(phase_or_name, name = nil)
      Delegators::Hooks.remove_boot_hook(phase_or_name, name)
    end
  end
end
