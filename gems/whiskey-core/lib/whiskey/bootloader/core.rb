# frozen_string_literal: true

require 'digest'
require 'singleton'
require 'json'

# Load the modular components
require_relative 'interfaces'
require_relative 'validation'
require_relative 'stress_testing'
require_relative 'diagnostics'
require_relative 'production_safety'
require_relative 'hook_management'
require_relative 'subsystem_management'
require_relative 'boot_sequence'
require_relative 'logging'

module Whiskey
  module Core
    module Bootloader
      # Core bootloader class that coordinates all modules
      # Production-hardened for long-term stability and thread safety
      class Core
        include Singleton
        include Analytics
        include DependencyManagement
        include Shutdown
        include ErrorRecovery
        include BootProfiles

        # Modular components
        include Validation
        include StressTesting
        include Diagnostics
        include ProductionSafety
        include HookManagement
        include SubsystemManagement
        include BootSequence
        include Logging

        # Current manifest schema version
        MANIFEST_VERSION = '2.0'

        # Thread-safe initialization with contract validation and lazy loading protection
        # Validates all included modules meet their interface contracts
        def initialize
          # Initialize shared mutexes first (required by all modules)
          @boot_mutex = Mutex.new
          @state_mutex = Mutex.new  # Separate mutex for state updates
          @hooks_mutex = Mutex.new  # Separate mutex for hook operations

          # Initialize all shared state variables (required by module contracts)
          @subsystem_registry = {}
          @boot_sequence_started = false
          @boot_sequence_completed = false
          @shutdown_started = false
          @shutdown_completed = false
          @boot_hooks = {
            before_boot: {},
            after_boot: {},
            before_subsystem: {},
            after_subsystem: {},
            before_shutdown: {},
            after_shutdown: {}
          }
          @boot_errors = []
          @shutdown_errors = []
          @subsystem_manifest = {}
          @failed_subsystems = {}

          # Boot timing metrics
          @boot_started_at = nil
          @boot_completed_at = nil
          @boot_duration = nil

          # Boot phases tracking for detailed diagnostics
          @boot_phases = {}

          # Track hook execution states for integrity
          @hook_execution_states = {}

          # Internal validation and diagnostics tracking (for specialized modules)
          @stress_test_log = []
          @validation_cache = {}

          # Validate module contracts for production safety
          validate_module_contracts!
        end

        private

        # Validate all included modules meet their interface contracts
        # Ensures cross-module consistency and proper initialization
        # @param strict [Boolean] if false, logs warnings instead of raising exceptions
        # @return [void]
        # @raise [RuntimeError] if any module contract validation fails and strict mode is enabled
        def validate_module_contracts!(strict: true)
          Interfaces::ContractValidator.validate_module_contracts!(self, strict: strict)
          Interfaces::ContractValidator.validate_cross_dependencies!(self, strict: strict)
        rescue StandardError => e
          # Log validation failure and re-raise for immediate attention
          safe_log_error("Module contract validation failed: #{e.message}")
          raise e if strict
        end

        public

        # Boot error registry for standardized error creation and logging
        # @private
        class BootErrorRegistry
          class << self
            # Create and log a standardized boot error
            # @param type [Symbol] error type (:bootloader, :subsystem, :hook, :integrity_check)
            # @param phase [Symbol] boot phase where error occurred
            # @param message [String] error message
            # @param subsystem [Symbol, nil] optional subsystem name
            # @param backtrace [Array<String>, nil] optional exception backtrace
            # @return [BootError] the created error object
            def create_and_log(type, phase, message, subsystem: nil, backtrace: nil)
              error = BootError.new(
                subsystem || type,
                phase,
                message,
                Time.now,
                backtrace || []
              )

              # Log the error with fallback logging
              safe_log_error("Boot error [#{type}:#{phase}]: #{message}" +
                           (subsystem ? " (subsystem: #{subsystem})" : ''))

              error
            end

            private

            # Safe error logging with fallback to stderr
            # @param message [String] error message to log
            def safe_log_error(message)
              if defined?(Whiskey::Core::Log)
                Whiskey::Core::Log.error("[Whiskey::Boot] #{message}")
              else
                warn "[Whiskey::Boot ERROR] #{message}"
              end
            rescue StandardError => e
              # Ultimate fallback - write directly to stderr
              warn "[Whiskey::Boot CRITICAL] Logging failed: #{e.message}"
              warn "[Whiskey::Boot ERROR] #{message}"
            end
          end
        end

        attr_reader :subsystem_registry, :boot_sequence_started, :boot_sequence_completed,
                    :shutdown_started, :shutdown_completed, :boot_errors, :shutdown_errors,
                    :boot_started_at, :boot_completed_at, :boot_duration, :boot_phases,
                    :failed_subsystems

        # Global bootloader for Ruby Whiskey framework
        # Production-hardened with thread safety and fault tolerance
        # @param profile [Symbol, nil] boot profile to use for selective loading
        # @param force_reload [Boolean] whether to reload config if already loaded
        # @param dry_run [Boolean] simulate boot without actually loading configs
        # @param parallel [Boolean] whether to boot subsystems in parallel
        # @return [Boolean] true if boot sequence completed successfully
        def boot!(profile: nil, force_reload: false, dry_run: false, parallel: false)
          @boot_mutex.synchronize do
            return true if @boot_sequence_completed && !force_reload

            # Thread-safe state updates
            update_boot_state do
              @boot_sequence_started = true
              @boot_started_at = Time.now
              @boot_errors.clear
              @boot_phases.clear
              @failed_subsystems.clear
              @hook_execution_states.clear
            end

            begin
              safe_log_info("🥃 Starting Ruby Whiskey boot sequence...#{profile ? " [profile: #{profile}]" : ''}")

              # Execute before_boot hooks with context
              boot_context = BootContext.new('bootloader', {}, 'Whiskey::Log', Whiskey.env, @boot_started_at, nil)
              unless execute_validated_hooks(:before_boot, boot_context)
                raise 'Before boot hooks failed - aborting boot sequence'
              end

              if dry_run
                safe_log_info('🧪 Dry run mode: simulating configuration loading...')
              else
                # Load unified configuration with error handling
                safe_log_info('Distilling configuration from project files...')
                begin
                  unless Whiskey::Config.load!(force_reload: force_reload)
                    safe_log_warn('No configuration file found - proceeding with defaults')
                  end
                rescue StandardError => e
                  safe_log_warn("Configuration loading failed: #{e.message} - proceeding with defaults")
                end

                # Clear config cache if force reloading
                ConfigCache.clear if force_reload
              end

              # Determine which subsystems to boot based on profile
              target_subsystems = determine_boot_targets(profile)

              # Boot target subsystems in priority order
              safe_log_info('Configuring subsystems from unified configuration...')
              boot_subsystems(target_subsystems, dry_run: dry_run, parallel: parallel)

              # Thread-safe completion updates
              completion_time = Time.now
              update_boot_state do
                @boot_completed_at = completion_time
                @boot_duration = @boot_completed_at - @boot_started_at
                @boot_sequence_completed = true
              end

              # Execute after_boot hooks with context
              boot_context.ended_at = @boot_completed_at
              execute_validated_hooks(:after_boot, boot_context)

              # Verify boot integrity
              verify_boot_integrity unless dry_run

              # Log signature summary
              log_signature_summary

              true
            rescue StandardError => e
              # Thread-safe error state updates
              failure_time = Time.now
              update_boot_state do
                @boot_sequence_started = false
                @boot_sequence_completed = false
                @boot_completed_at = failure_time
                @boot_duration = @boot_completed_at - @boot_started_at if @boot_started_at
              end

              # Use standardized error registry
              boot_error = BootErrorRegistry.create_and_log(:bootloader, :boot_sequence, e.message,
                                                            backtrace: e.backtrace)
              @boot_errors << boot_error

              safe_log_error("Boot sequence failed: #{e.message}")
              false
            end
          end
        end

        # Reload the entire framework
        # @return [Boolean] true if successfully reloaded
        def reload!
          @boot_mutex.synchronize do
            @boot_sequence_completed = false
            boot!(force_reload: true)
          end
        end

        # Check if framework has been booted
        # @return [Boolean] true if boot sequence completed
        def booted?
          @boot_sequence_completed
        end

        # Get boot status information
        # @return [Hash] boot status details
        def boot_status
          {
            started: @boot_sequence_started,
            completed: @boot_sequence_completed,
            shutdown_started: @shutdown_started,
            shutdown_completed: @shutdown_completed,
            registered_subsystems: @subsystem_registry.keys,
            failed_subsystems: @failed_subsystems.keys,
            config_loaded: defined?(Whiskey::Config) && Whiskey::Config.respond_to?(:loaded?) ? Whiskey::Config.loaded? : false,
            config_file: defined?(Whiskey::Config) && Whiskey::Config.respond_to?(:config_file_path) ? Whiskey::Config.config_file_path : nil,
            environment: Whiskey.env,
            boot_errors: @boot_errors.map(&:to_h),
            shutdown_errors: @shutdown_errors.map(&:to_h),
            cached_configs: ConfigCache.keys,
            boot_started_at: @boot_started_at,
            boot_completed_at: @boot_completed_at,
            boot_duration: @boot_duration
          }
        end

        # Get detailed boot manifest with schema versioning and digest
        # @return [Hash] detailed information about booted subsystems
        def manifest
          # Calculate digest of all subsystem names and statuses for build/test verification
          subsystem_data = @subsystem_manifest.map { |name, data| "#{name}:#{data[:status]}" }.sort.join('|')
          manifest_digest = Digest::SHA256.hexdigest(subsystem_data)

          {
            manifest_version: MANIFEST_VERSION,
            generated_at: Time.now,
            digest: manifest_digest,
            framework: {
              version: defined?(Whiskey::Core::VERSION) ? Whiskey::Core::VERSION : 'unknown',
              environment: Whiskey.env,
              booted: @boot_sequence_completed,
              boot_started_at: @boot_started_at,
              boot_completed_at: @boot_completed_at,
              boot_duration: @boot_duration,
              config_file: defined?(Whiskey::Config) && Whiskey::Config.respond_to?(:config_file_path) ? Whiskey::Config.config_file_path : nil,
              errors: @boot_errors.map(&:to_h),
              boot_phases: @boot_phases,
              hook_execution_states: @hook_execution_states
            },
            subsystems: @subsystem_manifest.dup,
            hooks: @boot_hooks.transform_values do |hooks|
              hooks.map do |name, data|
                if data.is_a?(Hash)
                  { name: name, order: data[:order] || 50, target: data[:target] }
                else
                  { name: name, order: 50, target: nil }
                end
              end.sort_by { |h| [h[:order], h[:name].to_s] }
            end
          }
        end

        # Class-level delegation methods for backward compatibility
        class << self
          # Delegate all instance methods to the singleton instance
          def method_missing(method_name, *args, **kwargs, &block)
            if instance.respond_to?(method_name)
              instance.send(method_name, *args, **kwargs, &block)
            else
              super
            end
          end

          def respond_to_missing?(method_name, include_private = false)
            instance.respond_to?(method_name, include_private) || super
          end
        end
      end
    end
  end
end
