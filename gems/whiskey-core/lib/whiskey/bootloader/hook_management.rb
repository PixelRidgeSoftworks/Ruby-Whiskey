# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Hook management module for boot lifecycle hooks
      #
      # Thread-Safety: Uses @hooks_mutex for all hook registry operations
      # Dependencies: Requires @boot_hooks, @hook_execution_states initialized
      # Lifecycle Phase: hook_registration (operates during hook setup phase)
      #
      # This module handles adding, removing, and executing hooks with deterministic ordering.
      # Provides safe cross-module delegation for hook execution with error handling.
      module HookManagement
        # Module contract implementation
        extend Interfaces::HookManagementContract
        # Register a custom boot hook for a specific phase with validation
        #
        # Thread-Safety: Uses @hooks_mutex for atomic hook registration
        # Cross-Module Usage: Called by subsystems during registration phase
        #
        # @param phase [Symbol] the phase (:before_boot, :after_boot, :before_subsystem, :after_subsystem, :before_shutdown, :after_shutdown)
        # @param name [Symbol] hook name
        # @param callable [Proc] the hook to execute
        # @param target [Symbol] optional target subsystem for scoped hooks
        # @param order [Integer] execution order (lower numbers execute first, default: 50)
        # @return [Boolean] true if hook was successfully registered
        # @raise [ArgumentError] if arguments are invalid or hook is not callable
        def register_boot_hook(phase, name = nil, callable = nil, target: nil, order: 50, &block)
          ensure_hooks_initialized!

          @hooks_mutex.synchronize do
            # Support both old and new interface for compatibility
            if name.nil? && callable.nil?
              raise ArgumentError, 'Invalid arguments for add_boot_hook'
            elsif callable.nil? && block_given?
              callable = block
            elsif name.is_a?(Proc) && callable.nil?
              callable = name
              name = phase
              phase = :before_boot # Default phase for backward compatibility
            end

            # Validate phase
            unless @boot_hooks.key?(phase)
              raise ArgumentError, "Invalid phase: #{phase}. Valid phases: #{@boot_hooks.keys.join(', ')}"
            end

            # Validate callable is actually callable
            raise ArgumentError, 'Hook must be callable (respond to :call)' unless callable.respond_to?(:call)

            # Validate hook name
            raise ArgumentError, 'Hook name cannot be nil or empty' if name.nil? || name.to_s.strip.empty?

            # Store hook with optional target scoping and execution order
            hook_data = {
              callable: callable,
              order: order,
              added_at: Time.now
            }
            hook_data[:target] = target if target

            @boot_hooks[phase][name.to_sym] = hook_data
            target_info = target ? " (target: #{target})" : ''
            safe_log_info("Registered boot hook: #{name} (phase: #{phase}, order: #{order})#{target_info}")
            true
          end
        end

        # Legacy alias for backward compatibility
        # @deprecated Use register_boot_hook instead
        def add_boot_hook(*args, **kwargs, &block)
          register_boot_hook(*args, **kwargs, &block)
        end

        # Unregister a boot hook
        #
        # Thread-Safety: Uses @hooks_mutex for atomic hook removal
        #
        # @param phase [Symbol] the phase
        # @param name [Symbol] hook name
        # @return [Boolean] true if hook was successfully unregistered
        def unregister_boot_hook(phase, name = nil)
          ensure_hooks_initialized!
          # Support old interface for compatibility
          if name.nil?
            name = phase
            # Try to find the hook in any phase
            @boot_hooks.each do |phase_key, hooks|
              if hooks.delete(name.to_sym)
                log_info("Removed boot hook: #{name} (phase: #{phase_key})")
                return true
              end
            end
            return false
          end

          return false unless @boot_hooks.key?(phase)

          @hooks_mutex.synchronize do
            removed = @boot_hooks[phase].delete(name.to_sym)
            if removed
              safe_log_info("Unregistered boot hook: #{name} (phase: #{phase})")
              true
            else
              false
            end
          end
        end

        # Legacy alias for backward compatibility
        # @deprecated Use unregister_boot_hook instead
        def remove_boot_hook(*args, **kwargs)
          unregister_boot_hook(*args, **kwargs)
        end

        # Execute boot hooks for a specific phase with safe delegation
        #
        # Thread-Safety: Reads hooks with mutex protection, executes outside lock
        # Error Handling: Uses BootErrorRegistry for structured error reporting
        # Cross-Module Usage: Called by BootSequence during boot phases
        #
        # @param phase [Symbol] the phase to execute
        # @param context [BootContext] boot context to pass to hooks
        # @param target [Symbol] optional target subsystem filter
        # @return [Boolean] true if all hooks executed successfully
        def execute_boot_hooks(phase = nil, context = nil, target: nil)
          ensure_hooks_initialized!
          # Support old interface for compatibility
          if phase.nil?
            # Old behavior: execute all hooks (for backward compatibility)
            return execute_boot_hooks(:before_boot, context) && execute_boot_hooks(:after_boot, context)
          end

          unless @boot_hooks.key?(phase)
            safe_log_warn("Unknown boot hook phase: #{phase}")
            return false
          end

          # Capture hooks with minimal lock time for thread safety
          hooks_to_execute = nil
          @hooks_mutex.synchronize do
            hooks_to_execute = @boot_hooks[phase].dup
          end

          # Sort hooks by order first, then by name for deterministic execution
          sorted_hooks = hooks_to_execute.sort_by do |name, hook_data|
            order = if hook_data.is_a?(Hash)
                      hook_data[:order] || 50
                    else
                      50 # Legacy hooks get default order
                    end
            [order, name.to_s] # Sort by order, then by name for determinism
          end

          sorted_hooks.each do |name, hook_data|
            # Handle both old format (direct callable) and new format (hash with metadata)
            if hook_data.is_a?(Hash)
              hook_callable = hook_data[:callable]
              hook_target = hook_data[:target]
              hook_order = hook_data[:order] || 50

              # Skip if target filtering is active and this hook doesn't match
              next if target && hook_target && hook_target != target
            else
              # Legacy format: hook_data is the callable directly
              hook_callable = hook_data
              hook_target = nil
              hook_order = 50
            end

            begin
              target_info = hook_target ? " (target: #{hook_target})" : ''
              safe_log_info("Executing #{phase} hook: #{name} (order: #{hook_order})#{target_info}")

              # Track hook execution state for integrity checking
              @hook_execution_states["#{phase}:#{name}"] = {
                started_at: Time.now,
                target: hook_target,
                order: hook_order
              }

              # Call hook with context if it accepts parameters
              if hook_callable.arity.positive? && context
                hook_callable.call(context)
              else
                hook_callable.call
              end

              # Mark successful completion
              @hook_execution_states["#{phase}:#{name}"][:completed_at] = Time.now
            rescue StandardError => e
              # Mark failed completion
              @hook_execution_states["#{phase}:#{name}"][:failed_at] = Time.now
              @hook_execution_states["#{phase}:#{name}"][:error] = e.message

              # Use standardized error registry
              boot_error = BootErrorRegistry.create_and_log(:hook, phase, "Hook #{name} failed: #{e.message}",
                                                            subsystem: hook_target, backtrace: e.backtrace)
              @boot_errors << boot_error
              return false
            end
          end

          true
        end

        # Execute hooks with validation and dependency checking
        #
        # Thread-Safety: Delegates to execute_boot_hooks which handles synchronization
        # Dependency Validation: Checks for failed prerequisite hooks
        #
        # @param phase [Symbol] the phase to execute
        # @param context [BootContext] boot context to pass to hooks
        # @param target [Symbol] optional target subsystem filter
        # @return [Boolean] true if all hooks executed successfully
        # @private
        def execute_validated_hooks(phase, context = nil, target: nil)
          ensure_hooks_initialized!

          # Validate dependencies for after_subsystem hooks
          if phase == :after_subsystem && target
            before_hook_key = "before_subsystem:#{target}"
            @state_mutex.synchronize do
              if @hook_execution_states.any? { |key, state| key.start_with?(before_hook_key) && state[:failed_at] }
                safe_log_warn("Skipping after_subsystem hooks for #{target} - before_subsystem hooks failed")
                return false
              end
            end
          end

          execute_boot_hooks(phase, context, target: target)
        end

        private

        # Ensure hook state is properly initialized with lazy loading protection
        # Thread-Safety: Uses @hooks_mutex for initialization check and setup
        # @return [void]
        def ensure_hooks_initialized!
          return if @boot_hooks && @hook_execution_states

          @hooks_mutex.synchronize do
            @boot_hooks ||= {
              before_boot: {},
              after_boot: {},
              before_subsystem: {},
              after_subsystem: {},
              before_shutdown: {},
              after_shutdown: {}
            }
            @hook_execution_states ||= {}
          end
        end
      end
    end
  end
end
