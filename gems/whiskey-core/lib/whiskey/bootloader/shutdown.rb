# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Shutdown functionality for graceful framework termination
      module Shutdown
        # Gracefully shutdown the framework in reverse order
        # @return [Boolean] true if shutdown completed successfully
        def shutdown!
          @boot_mutex.synchronize do
            return true if @shutdown_completed
            return false unless @boot_sequence_completed

            @shutdown_started = true
            shutdown_started_at = Time.now
            @shutdown_errors.clear

            begin
              log_info('🥃 Starting Ruby Whiskey shutdown sequence...')

              # Execute before_shutdown hooks
              shutdown_context = BootContext.new('bootloader', {}, 'Whiskey::Log', Whiskey.env, shutdown_started_at,
                                                 nil)
              execute_boot_hooks(:before_shutdown, shutdown_context)

              # Shutdown subsystems in reverse boot order
              shutdown_subsystems

              shutdown_completed_at = Time.now
              shutdown_duration = shutdown_completed_at - shutdown_started_at
              @shutdown_completed = true

              # Execute after_shutdown hooks
              shutdown_context.ended_at = shutdown_completed_at
              execute_boot_hooks(:after_shutdown, shutdown_context)

              log_info("🥃 Ruby Whiskey shutdown completed in #{'%.2f' % shutdown_duration}s")
              true
            rescue StandardError => e
              boot_error = BootError.new(:bootloader, :shutdown_sequence, e.message, Time.now, e.backtrace)
              @shutdown_errors << boot_error

              log_error("Shutdown sequence failed: #{e.message}")
              false
            end
          end
        end

        private

        # Shutdown subsystems in reverse order
        def shutdown_subsystems
          return if @subsystem_manifest.empty?

          # Get booted subsystems in reverse order
          shutdown_order = @subsystem_manifest.keys.reverse

          shutdown_order.each do |name|
            log_info("Shutting down #{name} subsystem...")

            info = @subsystem_registry[name]
            next unless info

            subsystem_module = info[:module]
            decanter = subsystem_module.decanter

            # Execute before_subsystem hooks for shutdown
            shutdown_context = BootContext.new(name, {}, 'Whiskey::Log', Whiskey.env, Time.now, nil)
            execute_boot_hooks(:before_shutdown, shutdown_context, target: name)

            # Call shutdown/teardown method if available
            if decanter.respond_to?(:shutdown)
              decanter.shutdown
            elsif decanter.respond_to?(:teardown)
              decanter.teardown
            end

            # Execute after_subsystem hooks for shutdown
            shutdown_context.ended_at = Time.now
            execute_boot_hooks(:after_shutdown, shutdown_context, target: name)

            log_info("✅ #{name} subsystem shut down")
          rescue StandardError => e
            boot_error = BootError.new(name, :shutdown, e.message, Time.now, e.backtrace)
            @shutdown_errors << boot_error
            log_error("Failed to shutdown #{name} subsystem: #{e.message}")
          end
        end
      end
    end
  end
end
