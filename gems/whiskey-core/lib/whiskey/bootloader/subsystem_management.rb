# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Subsystem management module for registration and lifecycle
      #
      # Thread-Safety: Uses @state_mutex for subsystem registry operations
      # Dependencies: Requires @subsystem_registry, @subsystem_manifest, @failed_subsystems initialized
      # Lifecycle Phase: subsystem_registration (operates during subsystem setup phase)
      #
      # This module handles subsystem registration, unregistration, and configuration caching.
      # Provides safe cross-module delegation for subsystem information retrieval.
      module SubsystemManagement
        # Module contract implementation
        extend Interfaces::SubsystemManagementContract
        # Register a subsystem with the global boot system
        #
        # Thread-Safety: Uses @state_mutex for atomic subsystem registration
        # Cross-Module Usage: Called during framework initialization and dynamic registration
        # Validation: Ensures subsystem has required decanter interface
        #
        # @param name [Symbol] the subsystem name (e.g., :ORM, :Web, :CLI)
        # @param subsystem_module [Module] the subsystem module
        # @param priority [Integer] boot priority (lower numbers boot first, default: 50)
        # @param depends_on [Array<Symbol>] list of subsystem dependencies
        # @return [Boolean] true if successfully registered
        # @raise [ArgumentError] if subsystem_module lacks required decanter interface
        def register_subsystem(name, subsystem_module, priority: 50, depends_on: [])
          ensure_subsystem_state_initialized!

          # Validate subsystem interface before registration
          unless subsystem_module.respond_to?(:decanter)
            safe_log_warn("Subsystem #{name} does not have a decanter - skipping registration")
            return false
          end

          # Extend subsystem with lifecycle DSL if it doesn't already have it
          if !(subsystem_module.respond_to?(:on_boot) && defined?(LifecycleEventsDSL)) && defined?(LifecycleEventsDSL)
            subsystem_module.extend(LifecycleEventsDSL)
          end

          @state_mutex.synchronize do
            @subsystem_registry[name.to_sym] = {
              module: subsystem_module,
              priority: priority,
              depends_on: depends_on.map(&:to_sym),
              registered_at: Time.now
            }
          end

          safe_log_info("Registered subsystem: #{name} (priority: #{priority}#{depends_on.any? ? ", depends_on: #{depends_on.join(', ')}" : ''})")
          true
        end

        # Unregister a subsystem (for testing or runtime modification)
        #
        # Thread-Safety: Uses @state_mutex for atomic subsystem removal
        # Production Protection: Blocked in production unless WHISKEY_ALLOW_MUTATIONS=true
        # Cross-Module Cleanup: Clears related config cache and manifests
        #
        # @param name [Symbol] the subsystem name
        # @return [Boolean] true if successfully unregistered
        def unregister_subsystem(name)
          ensure_subsystem_state_initialized!
          # Developer-safe guard: prevent destructive actions in production
          if respond_to?(:production_mutation_guard_active?) && production_mutation_guard_active?
            safe_log_warn('Subsystem unregistration blocked in production environment. Set WHISKEY_ALLOW_MUTATIONS=true to override.')
            return false
          end

          removed = nil
          @state_mutex.synchronize do
            removed = @subsystem_registry.delete(name.to_sym)
            @subsystem_manifest.delete(name.to_sym)
            @failed_subsystems.delete(name.to_sym)
          end

          # Clear config cache outside of mutex (may involve external calls)
          ConfigCache.clear(name.to_sym) if defined?(ConfigCache) && ConfigCache.respond_to?(:clear)

          if removed
            safe_log_info("Unregistered subsystem: #{name}")
            true
          else
            safe_log_warn("Subsystem #{name} was not registered")
            false
          end
        end

        # Get list of registered subsystems
        #
        # Thread-Safety: Returns snapshot of registry keys with mutex protection
        #
        # @return [Array<Symbol>] registered subsystem names
        def registered_subsystems
          ensure_subsystem_state_initialized!
          @state_mutex.synchronize { @subsystem_registry.keys.dup }
        end

        # Get a specific subsystem module
        #
        # Thread-Safety: Returns subsystem with mutex protection
        #
        # @param name [Symbol] the subsystem name
        # @return [Module, nil] the subsystem module or nil
        def subsystem(name)
          ensure_subsystem_state_initialized!
          @state_mutex.synchronize do
            info = @subsystem_registry[name.to_sym]
            info ? info[:module] : nil
          end
        end

        # Get cached config section for a subsystem with safe delegation
        #
        # Cross-Module Usage: Safely delegates to ConfigCache if available
        #
        # @param subsystem_name [Symbol] the subsystem name
        # @return [Hash, nil] cached config or nil
        def cached_config(subsystem_name)
          return unless defined?(ConfigCache) && ConfigCache.respond_to?(:get)

          ConfigCache.get(subsystem_name)
        end

        # Cache config section for a subsystem with safe delegation
        #
        # Cross-Module Usage: Safely delegates to ConfigCache if available
        #
        # @param subsystem_name [Symbol] the subsystem name
        # @param config [Hash] the config to cache
        # @return [Boolean] true if successfully cached
        def cache_config(subsystem_name, config)
          if defined?(ConfigCache) && ConfigCache.respond_to?(:set)
            ConfigCache.set(subsystem_name, config)
            true
          else
            safe_log_warn("ConfigCache not available - unable to cache config for #{subsystem_name}")
            false
          end
        end

        # Clear config cache for a subsystem or all subsystems with safe delegation
        #
        # Cross-Module Usage: Safely delegates to ConfigCache if available
        #
        # @param subsystem_name [Symbol, nil] the subsystem name, or nil for all
        # @return [Boolean] true if successfully cleared
        def clear_config_cache(subsystem_name = nil)
          if defined?(ConfigCache) && ConfigCache.respond_to?(:clear)
            ConfigCache.clear(subsystem_name)
            true
          else
            safe_log_warn('ConfigCache not available - unable to clear config cache')
            false
          end
        end

        private

        # Ensure subsystem state is properly initialized with lazy loading protection
        # Thread-Safety: Uses @state_mutex for initialization check and setup
        # @return [void]
        def ensure_subsystem_state_initialized!
          return if @subsystem_registry && @subsystem_manifest && @failed_subsystems

          @state_mutex.synchronize do
            @subsystem_registry ||= {}
            @subsystem_manifest ||= {}
            @failed_subsystems ||= {}
          end
        end
      end
    end
  end
end
