# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Boot sequence module for coordinating the actual boot process
      #
      # Thread-Safety: Uses @boot_mutex and @state_mutex for boot coordination
      # Dependencies: Requires @boot_phases, @subsystem_manifest, @failed_subsystems initialized
      # Lifecycle Phase: boot_sequence (operates during main boot execution phase)
      #
      # This module handles the main boot logic, subsystem loading, and verification.
      # Provides safe cross-module delegation for boot execution and integrity checking.
      module BootSequence
        # Module contract implementation
        extend Interfaces::BootSequenceContract

        private

        # Boot all registered subsystems in priority order
        # Each subsystem should have a decanter that responds to load_from_config
        # @param target_subsystems [Hash] subsystems to boot (for profile support)
        # @param dry_run [Boolean] whether to simulate boot without actual loading
        # @param parallel [Boolean] whether to boot subsystems in parallel
        def boot_subsystems(target_subsystems = nil, dry_run: false, parallel: false)
          subsystems_to_boot = target_subsystems || @subsystem_registry
          return if subsystems_to_boot.empty?

          ordered_subsystems = subsystems_by_priority(subsystems_to_boot)

          if parallel && ordered_subsystems.size > 1
            # Boot subsystems in parallel using threads
            threads = ordered_subsystems.map do |name, info|
              Thread.new { boot_single_subsystem(name, info, dry_run) }
            end

            # Wait for all threads to complete
            threads.each(&:join)
          else
            # Boot subsystems sequentially
            ordered_subsystems.each do |name, info|
              boot_single_subsystem(name, info, dry_run)
            end
          end
        end

        # Boot a single subsystem (thread-safe for parallel execution)
        # @param name [Symbol] subsystem name
        # @param info [Hash] subsystem registry info
        # @param dry_run [Boolean] whether to simulate boot
        def boot_single_subsystem(name, info, dry_run)
          subsystem_module = info[:module]

          begin
            log_info("Configuring #{name} subsystem... (priority: #{info[:priority]})")

            # Track boot phase start
            phase_start = Time.now
            @boot_phases[name] = { started_at: phase_start }

            # Create subsystem boot context
            subsystem_config = dry_run ? {} : (cached_config(name) || {})
            boot_context = BootContext.new(name, subsystem_config, 'Whiskey::Log', Whiskey.env, phase_start, nil)

            # Execute before_subsystem hooks with target filtering
            execute_boot_hooks(:before_subsystem, boot_context, target: name)

            decanter = subsystem_module.decanter
            success = false
            config_source = :cache
            config_checksum = nil

            # Enforce basic decanter interface check
            unless decanter.respond_to?(:load_from_config) || decanter.respond_to?(:configure_from_config)
              error_msg = 'Decanter missing load_from_config or configure_from_config method'
              mark_subsystem_failed(name, error_msg, info, phase_start)
              return
            end

            # Check for cached config first
            cached = cached_config(name)
            if cached && !dry_run
              log_info("Using cached configuration for #{name}")
              success = true
              config_source = :cache
              config_checksum = Digest::SHA256.hexdigest(cached.to_s)
            elsif dry_run
              log_info("🧪 Dry run: simulating #{name} configuration")
              success = true
              config_source = :dry_run
            else
              # Try to load from unified config
              section_config = get_subsystem_config(name)

              if decanter.respond_to?(:load_from_config)
                success = decanter.load_from_config
                if success && section_config.any?
                  cache_config(name, section_config)
                  config_source = :file
                  config_checksum = Digest::SHA256.hexdigest(section_config.to_s)
                  log_info("✅ #{name} subsystem configured from unified config")
                else
                  success = true # Allow defaults
                  log_warn("⚠️  #{name} subsystem config not found - using defaults")
                end
              elsif decanter.respond_to?(:configure_from_config)
                # Alternative method name for future subsystems
                success = decanter.configure_from_config
                if success && section_config.any?
                  cache_config(name, section_config)
                  config_source = :file
                  config_checksum = Digest::SHA256.hexdigest(section_config.to_s)
                  log_info("✅ #{name} subsystem configured from unified config")
                else
                  success = true # Allow defaults
                  log_warn("⚠️  #{name} subsystem config not found - using defaults")
                end
              end
            end

            phase_end = Time.now
            boot_time = phase_end - phase_start
            boot_context.ended_at = phase_end

            # Update boot phase tracking
            @boot_phases[name][:ended_at] = phase_end
            @boot_phases[name][:duration] = boot_time

            # Get subsystem configuration for enabled check
            section_config = cached || get_subsystem_config(name)
            enabled = section_config.fetch('Enabled', true)

            # Count hooks for this subsystem
            hook_count = @boot_hooks.values.sum do |hooks|
              hooks.count do |_, hook_data|
                if hook_data.is_a?(Hash)
                  hook_data[:target] == name
                else
                  false # Legacy hooks don't have target scoping
                end
              end
            end

            # Record enhanced subsystem manifest
            @subsystem_manifest[name] = {
              status: success ? :configured : :warning,
              priority: info[:priority],
              depends_on: info[:depends_on],
              registered_at: info[:registered_at],
              boot_time: boot_time,
              config_cached: cached_config(name) ? true : false,
              enabled: enabled,
              config_source: config_source,
              config_checksum: config_checksum,
              hook_count: hook_count
            }

            # Execute after_subsystem hooks with target filtering
            execute_boot_hooks(:after_subsystem, boot_context, target: name)
          rescue StandardError => e
            mark_subsystem_failed(name, e.message, info, phase_start, e.backtrace)
          end
        end

        # Get subsystem configuration from unified config
        # @param name [Symbol] subsystem name
        # @return [Hash] configuration hash
        def get_subsystem_config(name)
          return {} unless defined?(Whiskey::Config) && Whiskey::Config.respond_to?(:section)

          Whiskey::Config.section(name.to_s) || {}
        end

        # Verify boot integrity after successful boot
        def verify_boot_integrity
          unbooted_subsystems = @subsystem_registry.keys - @subsystem_manifest.keys

          if unbooted_subsystems.any?
            log_warn("⚠️  Unbooted subsystems detected: #{unbooted_subsystems.join(', ')}")
            unbooted_subsystems.each do |subsystem|
              boot_error = BootError.new(subsystem, :integrity_check, 'Subsystem registered but not booted', Time.now,
                                         [])
              @boot_errors << boot_error
            end
          else
            log_info('✅ Boot integrity verified: all registered subsystems booted successfully')
          end
        end

        # Log signature summary on successful boot
        def log_signature_summary
          subsystem_count = @subsystem_manifest.size
          failed_count = @failed_subsystems.size
          duration_str = @boot_duration ? format('%.2f', @boot_duration) : 'unknown'

          if @boot_errors.empty?
            log_info("🥃 Whiskey distilled #{subsystem_count} subsystems in #{duration_str}s [env: #{Whiskey.env}]")
          else
            warning_text = failed_count.positive? ? " with #{failed_count} failure(s)" : " with #{@boot_errors.length} warning(s)"
            log_warn("🥃 Whiskey distilled #{subsystem_count} subsystems in #{duration_str}s [env: #{Whiskey.env}]#{warning_text}")
          end
        end

        # Mark a subsystem as failed with standardized error handling
        # @param name [Symbol] subsystem name
        # @param error_message [String] error message
        # @param info [Hash] subsystem registry info
        # @param phase_start [Time] when the phase started
        # @param backtrace [Array<String>] optional exception backtrace
        # @private
        def mark_subsystem_failed(name, error_message, info, phase_start, backtrace = [])
          phase_end = Time.now
          boot_time = phase_end - phase_start

          # Thread-safe failed subsystem tracking
          update_boot_state do
            @failed_subsystems[name] = {
              error: error_message,
              failed_at: phase_end,
              boot_time: boot_time,
              priority: info[:priority],
              depends_on: info[:depends_on]
            }
          end

          # Update boot phase tracking
          @boot_phases[name] ||= { started_at: phase_start }
          @boot_phases[name][:ended_at] = phase_end
          @boot_phases[name][:duration] = boot_time
          @boot_phases[name][:failed] = true

          # Create standardized error
          boot_error = BootErrorRegistry.create_and_log(:subsystem, :boot_subsystem, error_message,
                                                        subsystem: name, backtrace: backtrace)
          @boot_errors << boot_error

          safe_log_error("❌ #{name} subsystem failed: #{error_message}")
        end

        # Idempotent shutdown with graceful fallbacks
        # Enhanced to work even if boot failed partway through
        # @return [Boolean] true if shutdown completed successfully
        # @private
        def graceful_shutdown!
          return true if @shutdown_completed

          @boot_mutex.synchronize do
            return true if @shutdown_completed

            update_boot_state do
              @shutdown_started = true
            end

            begin
              safe_log_info('🥃 Beginning graceful Whiskey framework shutdown...')

              # Execute before_shutdown hooks if any exist
              shutdown_context = BootContext.new('bootloader', {}, 'Whiskey::Log', Whiskey.env, Time.now, nil)
              execute_validated_hooks(:before_shutdown, shutdown_context)

              # Attempt to shut down each booted subsystem in reverse boot order
              shutdown_subsystems_gracefully if @subsystem_manifest.any?

              # Clear state but preserve error history for debugging
              update_boot_state do
                @boot_sequence_completed = false
                @boot_sequence_started = false
              end

              # Execute after_shutdown hooks
              execute_validated_hooks(:after_shutdown, shutdown_context)

              update_boot_state do
                @shutdown_completed = true
              end

              safe_log_info('🥃 Whiskey framework shutdown completed')
              true
            rescue StandardError => e
              # Even if shutdown fails, mark as completed to prevent loops
              update_boot_state do
                @shutdown_completed = true
              end

              shutdown_error = BootErrorRegistry.create_and_log(:bootloader, :shutdown, e.message,
                                                                backtrace: e.backtrace)
              @shutdown_errors << shutdown_error

              safe_log_error("Shutdown failed: #{e.message}")
              false
            end
          end
        end

        # Shutdown subsystems gracefully in reverse boot order
        # @private
        def shutdown_subsystems_gracefully
          # Shut down in reverse priority order (highest priority first)
          shutdown_order = @subsystem_manifest.sort_by { |name, data| [-data[:priority], name.to_s] }

          shutdown_order.each_key do |name|
            subsystem_info = @subsystem_registry[name]
            next unless subsystem_info && subsystem_info[:module]

            subsystem_module = subsystem_info[:module]
            if subsystem_module.respond_to?(:shutdown) ||
               (subsystem_module.respond_to?(:decanter) && subsystem_module.decanter.respond_to?(:shutdown))

              safe_log_info("Shutting down #{name} subsystem...")

              if subsystem_module.respond_to?(:shutdown)
                subsystem_module.shutdown
              elsif subsystem_module.decanter.respond_to?(:shutdown)
                subsystem_module.decanter.shutdown
              end

              safe_log_info("✅ #{name} subsystem shutdown completed")
            end
          rescue StandardError => e
            shutdown_error = BootErrorRegistry.create_and_log(:subsystem, :shutdown, e.message,
                                                              subsystem: name, backtrace: e.backtrace)
            @shutdown_errors << shutdown_error
            safe_log_error("⚠️  #{name} subsystem shutdown failed: #{e.message}")
          end
        end

        # Ensure boot state is properly initialized with lazy loading protection
        # Thread-Safety: Uses @state_mutex for initialization check and setup
        # @return [void]
        def ensure_boot_state_initialized!
          return if @boot_phases && @subsystem_manifest && @failed_subsystems

          @state_mutex.synchronize do
            @boot_phases ||= {}
            @subsystem_manifest ||= {}
            @failed_subsystems ||= {}
          end
        end
      end
    end
  end
end
