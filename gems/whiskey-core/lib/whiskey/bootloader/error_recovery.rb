# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Error recovery functionality for failed subsystems
      module ErrorRecovery
        # Attempt to recover a failed subsystem
        # @param name [Symbol] the subsystem name to recover
        # @return [Boolean] true if recovery successful
        def recover_subsystem(name)
          name = name.to_sym
          return false unless @failed_subsystems.key?(name)

          log_info("🔄 Attempting to recover failed subsystem: #{name}")

          info = @subsystem_registry[name]
          return false unless info

          begin
            # Remove from failed list and try booting again
            @failed_subsystems.delete(name)
            boot_single_subsystem(name, info, false)

            if @subsystem_manifest[name] && @subsystem_manifest[name][:status] != :error
              log_info("✅ Successfully recovered subsystem: #{name}")
              true
            else
              log_warn("⚠️  Failed to recover subsystem: #{name}")
              false
            end
          rescue StandardError => e
            log_error("Failed to recover subsystem #{name}: #{e.message}")
            false
          end
        end

        private

        # Mark a subsystem as failed but continue booting others
        # @param name [Symbol] subsystem name
        # @param error_message [String] error description
        # @param info [Hash] subsystem registry info
        # @param phase_start [Time] when boot phase started
        # @param backtrace [Array<String>] error backtrace
        def mark_subsystem_failed(name, error_message, info, phase_start, backtrace = [])
          boot_error = BootError.new(name, :subsystem_boot, error_message, Time.now, backtrace)
          @boot_errors << boot_error
          @failed_subsystems[name] = {
            error: error_message,
            failed_at: Time.now,
            info: info
          }

          log_error("Failed to configure #{name} subsystem: #{error_message}")

          # Update boot phase tracking on error
          phase_end = Time.now
          @boot_phases[name] ||= { started_at: phase_start }
          @boot_phases[name][:ended_at] = phase_end
          @boot_phases[name][:duration] = phase_end - phase_start
          @boot_phases[name][:error] = error_message

          @subsystem_manifest[name] = {
            status: :error,
            priority: info[:priority],
            depends_on: info[:depends_on] || [],
            registered_at: info[:registered_at],
            error: error_message,
            config_cached: false,
            enabled: false,
            config_source: :error,
            config_checksum: nil,
            hook_count: 0,
            boot_time: phase_end - phase_start
          }
        end
      end
    end
  end
end
