# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Logging module that delegates to the master Whiskey::Core::Log system
      #
      # Thread-Safety: Uses @state_mutex for state update synchronization
      # Dependencies: Requires @state_mutex initialized for update_boot_state helper
      # Lifecycle Phase: initialization (provides logging throughout all phases)
      #
      # This module provides bootloader-specific logging helpers using the existing logger infrastructure.
      # Delegates all logging to the master Whiskey::Core::Log system with bootloader prefixes.
      module Logging
        # Module contract implementation
        extend Interfaces::LoggingContract
        # Log info message using the master logger with bootloader prefix
        # @param message [String] the message to log
        def log_info(message)
          Whiskey::Core::Log.info("[Whiskey::Boot] #{message}")
        end

        # Log warning message using the master logger with bootloader prefix
        # @param message [String] the warning message to log
        def log_warn(message)
          Whiskey::Core::Log.warn("[Whiskey::Boot] #{message}")
        end

        # Log error message using the master logger with bootloader prefix
        # @param message [String] the error message to log
        def log_error(message)
          Whiskey::Core::Log.error("[Whiskey::Boot] #{message}")
        end

        # Safe logging methods with fallback to stderr (for critical boot failures)
        # @param message [String] the message to log
        # @private
        def safe_log_info(message)
          Whiskey::Core::Log.info("[Whiskey::Boot] #{message}")
        rescue StandardError => e
          warn "[Whiskey::Boot CRITICAL] Info logging failed: #{e.message}"
          warn "[Whiskey::Boot INFO] #{message}"
        end

        # @param message [String] the warning message to log
        # @private
        def safe_log_warn(message)
          Whiskey::Core::Log.warn("[Whiskey::Boot] #{message}")
        rescue StandardError => e
          warn "[Whiskey::Boot CRITICAL] Warning logging failed: #{e.message}"
          warn "[Whiskey::Boot WARN] #{message}"
        end

        # @param message [String] the error message to log
        # @private
        def safe_log_error(message)
          Whiskey::Core::Log.error("[Whiskey::Boot] #{message}")
        rescue StandardError => e
          warn "[Whiskey::Boot CRITICAL] Error logging failed: #{e.message}"
          warn "[Whiskey::Boot ERROR] #{message}"
        end

        # Thread-safe state update helper
        # @param block [Block] block to execute within synchronized context
        # @return [void]
        # @private
        def update_boot_state(&block)
          @state_mutex.synchronize(&block)
        end

        # Apply ANSI colorization for development environment
        # @param message [String] the message to colorize
        # @param level [Symbol] the log level (:info, :warn, :error)
        # @return [String] colorized message or original message
        # @private
        def colorize_log(message, level)
          # Only colorize in development and if output is a TTY
          return message unless Whiskey.development? && $stdout.respond_to?(:isatty) && $stdout.isatty

          case level
          when :info
            "\e[36m#{message}\e[0m" # Soft cyan for info
          when :warn
            "\e[33m#{message}\e[0m" # Soft yellow for warnings
          when :error
            "\e[31m#{message}\e[0m" # Soft red for errors
          else
            message
          end
        rescue StandardError
          # If colorization fails, return plain message
          message
        end
      end
    end
  end
end
