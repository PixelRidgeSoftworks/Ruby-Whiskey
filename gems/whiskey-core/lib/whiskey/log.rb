# frozen_string_literal: true

##
# Ruby Whiskey Framework - Logging System
#
# Unified logging system for Ruby Whiskey framework using a modular adapter system
# for flexible logging backends. Provides thread-safe operations with configurable
# formatters, environment-aware verbosity, and structured metadata support.
#
# @author PixelRidge Softworks
# @version 2.0.0
# @since 1.0.0

module Whiskey
  module Core
    # Unified logging system for Ruby Whiskey framework
    # Uses a modular adapter system for flexible logging backends
    class Log
      # Log level hierarchy for environment-aware filtering
      LOG_LEVELS = {
        debug: 0,
        info: 1,
        warn: 2,
        error: 3
      }.freeze

      # Default log level thresholds per environment
      ENV_LOG_LEVELS = {
        'development' => :debug,
        'test' => :warn,
        'production' => :info
      }.freeze

      # Rate limiting for adapter warnings - limit warnings to once per period
      WARNING_RATE_LIMIT_SECONDS = 60

      # Base class for logger adapters (convenience class, not required)
      # @abstract Subclass and implement {#log} to create a logger adapter
      class LoggerAdapter
        # Log a message at the specified level
        # @param level [Symbol] log level (:info, :warn, :error, :debug)
        # @param message [String] formatted message to log
        # @return [Boolean] true if logging succeeded, false otherwise
        def log(level, message)
          raise NotImplementedError, "#{self.class} must implement #log"
        end
      end

      # ORM logger adapter for Whiskey::ORM::Log
      class ORMAdapter < LoggerAdapter
        def log(level, message)
          return false unless defined?(Whiskey::ORM::Log)
          return false unless Whiskey::ORM::Log.respond_to?(level)

          Whiskey::ORM::Log.send(level, message)
          true
        rescue StandardError => e
          # Emit debug warning via StdoutAdapter when ORM fails
          StdoutAdapter.new.log(:warn, "ORMAdapter failed: #{e.message}")
          false
        end
      end

      # STDOUT/STDERR fallback adapter with level prefixes and multiline support
      class StdoutAdapter < LoggerAdapter
        def log(level, message)
          level_prefix = case level
                         when :info then '[INFO]'
                         when :warn then '[WARN]'
                         when :error then '[ERROR]'
                         when :debug then '[DEBUG]'
                         else "[#{level.to_s.upcase}]"
                         end

          # Use stderr for error messages
          output_stream = level == :error ? $stderr : $stdout

          # Handle multiline messages with proper indentation
          lines = message.split("\n")
          if lines.size > 1
            output_stream.puts "#{level_prefix} #{lines.first}"
            lines[1..].each do |line|
              output_stream.puts "#{' ' * level_prefix.length} #{line}"
            end
          else
            output_stream.puts "#{level_prefix} #{message}"
          end

          true
        rescue StandardError
          false
        end
      end

      class << self
        # Get currently registered adapters (thread-safe)
        # @return [Array] list of registered adapters
        def adapters
          ensure_initialized
          @mutex.synchronize { @adapters.dup }
        end

        # Get current log formatter (thread-safe)
        # @return [Proc] the formatter proc
        def formatter
          ensure_initialized
          @mutex.synchronize { @formatter }
        end

        # Get health metrics for a specific adapter
        # @param adapter [Object] the adapter instance
        # @return [Hash] health metrics for the adapter
        def adapter_health(adapter)
          ensure_initialized
          @mutex.synchronize do
            @adapter_health[adapter]&.dup || {}
          end
        end

        # Set optional warning handler for adapter failures
        # @param handler [Proc] proc that takes (adapter, exception, message) when adapter fails
        # @return [void]
        def warning_handler=(handler)
          unless handler.nil? || handler.respond_to?(:call)
            raise ArgumentError, "Warning handler must be callable (respond to :call) or nil, got #{handler.class}"
          end

          ensure_initialized
          @mutex.synchronize do
            @warning_handler = handler
          end
        end

        # Get current warning handler
        # @return [Proc, nil] the warning handler proc or nil
        def warning_handler
          ensure_initialized
          @mutex.synchronize { @warning_handler }
        end

        # Use/register a new logger adapter (duck-typed)
        # @param adapter [Object] adapter that responds to :log
        # @param priority [Symbol] :prepend (default) adds to front, :append adds to end
        # @return [void]
        def use(adapter, priority: :prepend)
          raise ArgumentError, 'Adapter must respond to :log method' unless adapter.respond_to?(:log)

          unless %i[prepend append].include?(priority)
            raise ArgumentError, "Priority must be :prepend or :append, got #{priority}"
          end

          ensure_initialized
          @mutex.synchronize do
            if priority == :prepend
              @adapters.unshift(adapter)
            else
              @adapters.push(adapter)
            end
          end
        end

        # Set a custom log formatter
        # @param formatter [Proc] proc that takes (level, env, msg, metadata) and returns formatted string
        # @return [void]
        # @raise [ArgumentError] if formatter doesn't respond to :call
        def formatter=(formatter)
          unless formatter.respond_to?(:call)
            raise ArgumentError, "Formatter must be callable (respond to :call), got #{formatter.class}"
          end

          ensure_initialized
          @mutex.synchronize do
            @formatter = formatter
          end
        end

        # Set minimum log level for current environment
        # @param level [Symbol] minimum level (:debug, :info, :warn, :error)
        # @return [void]
        def level=(level)
          unless LOG_LEVELS.key?(level)
            raise ArgumentError, "Invalid log level: #{level}. Valid levels: #{LOG_LEVELS.keys.join(', ')}"
          end

          ensure_initialized
          @mutex.synchronize do
            @min_level = level
          end
        end

        # Get current minimum log level
        # @return [Symbol] current minimum log level
        def level
          ensure_initialized
          @mutex.synchronize { @min_level }
        end

        # Reset log system to default state - safely clears all adapters and resets formatter
        # Used in tests and framework reloads to ensure clean state
        # @return [void]
        def reset!
          @mutex ||= Mutex.new
          @mutex.synchronize do
            @adapters = [ORMAdapter.new, StdoutAdapter.new]
            @formatter = default_formatter
            @min_level = current_env_level
            @adapter_health = {}
            @warning_handler = nil
            @env = nil # Reset cached environment
            @formatter_fallback_count = 0 # Reset fallback usage count
          end
        end

        # Get built-in JSON formatter for machine-readable logs
        # @return [Proc] JSON formatter proc
        def json_formatter
          proc do |level, env, msg, metadata = nil|
            timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S.%3N')

            log_entry = {
              timestamp: timestamp,
              level: level.to_s.upcase,
              environment: env,
              message: msg
            }

            # Add metadata if present
            log_entry[:metadata] = metadata if metadata && !metadata.empty?

            # Simple JSON generation without external dependencies
            begin
              log_entry.to_json
            rescue StandardError
              manual_json_format(log_entry)
            end
          end
        end

        # Get comprehensive diagnostics for the logging system
        # @return [Hash] adapter status, health metrics, and configuration
        def diagnostics
          ensure_initialized

          # Capture current state with minimal lock time
          current_adapters, current_formatter, current_level, health_data, fallback_count = nil
          @mutex.synchronize do
            current_adapters = @adapters.dup
            current_formatter = @formatter
            current_level = @min_level
            health_data = @adapter_health.dup
            fallback_count = @formatter_fallback_count || 0
          end

          {
            environment: defined?(Whiskey) && Whiskey.respond_to?(:env) ? Whiskey.env : 'unknown',
            min_level: current_level,
            adapters: current_adapters.map.with_index do |adapter, index|
              adapter_name = adapter.class.name
              health = health_data[adapter] || {}
              success_count = health[:success_count] || 0
              error_count = health[:error_count] || 0
              total_attempts = success_count + error_count

              # Calculate error ratio and warning timestamps
              error_ratio = total_attempts.positive? ? (error_count.to_f / total_attempts).round(3) : 0.0
              consecutive_failures = health[:consecutive_failures] || 0
              last_warning_time = health[:last_warning_time]

              # Calculate next allowed warning time
              next_allowed_warning = (last_warning_time + WARNING_RATE_LIMIT_SECONDS if last_warning_time)

              {
                index: index,
                class: adapter_name,
                status: health[:last_success] ? 'healthy' : 'unknown',
                disabled: false, # Adapters are never disabled with rate limiting
                last_success: health[:last_success],
                last_error: health[:last_error],
                last_warning_time: last_warning_time,
                next_allowed_warning: next_allowed_warning,
                success_count: success_count,
                error_count: error_count,
                error_ratio: error_ratio,
                consecutive_failures: consecutive_failures
              }
            end,
            formatter: current_formatter.class.name,
            total_adapters: current_adapters.size
          }
        end

        # Log info message with optional structured metadata
        # @param message [String] the message to log
        # @param metadata [Hash] optional structured metadata (default: nil)
        def info(message, metadata = nil)
          delegate_log(:info, message, metadata)
        end

        # Log warning message with optional structured metadata
        # @param message [String] the warning message to log
        # @param metadata [Hash] optional structured metadata (default: nil)
        def warn(message, metadata = nil)
          delegate_log(:warn, message, metadata)
        end

        # Log error message with optional structured metadata
        # @param message [String] the error message to log
        # @param metadata [Hash] optional structured metadata (default: nil)
        def error(message, metadata = nil)
          delegate_log(:error, message, metadata)
        end

        # Log debug message with optional structured metadata
        # @param message [String] the debug message to log
        # @param metadata [Hash] optional structured metadata (default: nil)
        def debug(message, metadata = nil)
          delegate_log(:debug, message, metadata)
        end

        private

        # Ensure adapters and formatter are initialized (thread-safe)
        def ensure_initialized
          return if @adapters && @formatter && @min_level && @adapter_health

          @mutex ||= Mutex.new
          @mutex.synchronize do
            return if @adapters && @formatter && @min_level && @adapter_health

            @adapters ||= [ORMAdapter.new, StdoutAdapter.new]
            @formatter ||= default_formatter
            @min_level ||= current_env_level
            @adapter_health ||= {}
            @warning_handler ||= nil
            @env ||= nil # Initialize cached environment
            @formatter_fallback_count ||= 0 # Initialize fallback usage count
          end
        end

        # Get cached environment with lazy refresh
        # @return [String] current environment name
        def cached_environment
          # Quick read without lock for performance
          return @env if @env

          # Cache miss - resolve and cache environment
          resolved_env = defined?(Whiskey) && Whiskey.respond_to?(:env) ? Whiskey.env : 'development'
          @mutex.synchronize { @env = resolved_env }
          resolved_env
        end

        # Minimal fallback formatter for when main formatter fails
        # @return [Proc] simple fallback formatter
        def fallback_formatter
          proc do |level, env, msg, _metadata = nil|
            timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S.%3N')
            "[#{timestamp}] [#{env}] [#{level.to_s.upcase}] #{msg}"
          end
        end

        # Get current environment's default log level
        # @return [Symbol] default log level for current environment
        def current_env_level
          env = defined?(Whiskey) && Whiskey.respond_to?(:env) ? Whiskey.env : 'development'
          ENV_LOG_LEVELS[env] || :info
        end

        # Check if message should be logged based on level filtering
        # @param level [Symbol] log level to check
        # @return [Boolean] true if message should be logged
        def should_log?(level)
          ensure_initialized

          # Quick read without lock for performance
          min_level_num = LOG_LEVELS[@min_level] || LOG_LEVELS[:info]
          current_level_num = LOG_LEVELS[level] || LOG_LEVELS[:info]

          current_level_num >= min_level_num
        end

        # Update adapter health tracking with rate-limited warning support and minimal lock time
        # @param adapter [Object] the adapter instance
        # @param success [Boolean] whether the operation succeeded
        # @param error [Exception, nil] error if operation failed
        def update_adapter_health(adapter, success, error = nil)
          timestamp = Time.now

          @mutex.synchronize do
            @adapter_health[adapter] ||= { success_count: 0, error_count: 0, consecutive_failures: 0 }

            if success
              @adapter_health[adapter][:success_count] += 1
              @adapter_health[adapter][:last_success] = timestamp
              @adapter_health[adapter][:consecutive_failures] = 0 # Reset failure count on success
            else
              @adapter_health[adapter][:error_count] += 1
              @adapter_health[adapter][:consecutive_failures] += 1
              @adapter_health[adapter][:last_error] = { timestamp: timestamp, message: error&.message }
            end
          end
        end

        # Check if warning should be emitted for adapter failure (rate limited)
        # @param adapter [Object] the adapter instance
        # @return [Boolean] true if warning should be emitted
        def should_warn_for_adapter?(adapter)
          ensure_initialized
          timestamp = Time.now

          @mutex.synchronize do
            health = @adapter_health[adapter] ||= { success_count: 0, error_count: 0, consecutive_failures: 0 }
            last_warning = health[:last_warning_time]

            # Allow warning if no previous warning or rate limit period has passed
            if last_warning.nil? || (timestamp - last_warning) >= WARNING_RATE_LIMIT_SECONDS
              health[:last_warning_time] = timestamp
              true
            else
              false
            end
          end
        end

        # Get formatter source location if available
        # @param formatter [Proc] the formatter proc
        # @return [String, nil] source location or nil if unavailable
        def formatter_source_location(formatter)
          return nil unless formatter.respond_to?(:source_location)

          location = formatter.source_location
          return nil unless location && location.size >= 2

          "#{location[0]}:#{location[1]}"
        rescue StandardError
          nil # Return nil if source_location fails
        end

        # Call warning handler if set, with rate limiting respected
        # @param adapter [Object] the adapter instance
        # @param exception [Exception, nil] the exception if any
        # @param message [String] the failure message
        def call_warning_handler(adapter, exception, message)
          handler = nil
          @mutex.synchronize { handler = @warning_handler }

          return unless handler

          begin
            handler.call(adapter, exception, message)
          rescue StandardError => e
            # Warning handler itself failed - log via StdoutAdapter
            StdoutAdapter.new.log(:warn, "Warning handler failed: #{e.message}")
          end
        end

        # Manual JSON formatting fallback when to_json is not available
        # @param hash [Hash] hash to convert to JSON
        # @return [String] JSON string
        def manual_json_format(hash)
          parts = hash.map do |key, value|
            key_str = "\"#{key}\""
            value_str = case value
                        when String
                          "\"#{value.gsub('"', '\\"')}\""
                        when Numeric, TrueClass, FalseClass
                          value.to_s
                        when Hash
                          manual_json_format(value)
                        when NilClass
                          'null'
                        else
                          "\"#{value.to_s.gsub('"', '\\"')}\""
                        end
            "#{key_str}:#{value_str}"
          end
          "{#{parts.join(',')}}"
        end

        # Default formatter with millisecond precision timestamp, environment, and optional metadata
        # @return [Proc] default formatter proc
        def default_formatter
          proc do |_level, env, msg, metadata = nil|
            timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S.%3N')
            base_msg = "[#{timestamp}] [#{env}] #{msg}"

            if metadata && !metadata.empty?
              metadata_str = metadata.map { |k, v| "#{k}=#{v}" }.join(' ')
              "#{base_msg} | #{metadata_str}"
            else
              base_msg
            end
          end
        end

        # Helper method to format message using current formatter with failure protection
        # @param level [Symbol] log level
        # @param message [String] raw message
        # @param metadata [Hash, nil] optional structured metadata
        # @return [String] formatted message
        def format_message(level, message, metadata = nil)
          ensure_initialized

          # Capture formatter with minimal lock time
          formatter_proc = nil
          @mutex.synchronize { formatter_proc = @formatter }

          # Get cached environment without repeated Whiskey.env calls
          env = cached_environment

          # Format outside of lock with failure protection
          begin
            formatter_proc.call(level, env, message, metadata)
          rescue StandardError => e
            # Formatter failed - increment fallback count and use fallback formatter
            @mutex.synchronize { @formatter_fallback_count += 1 }
            StdoutAdapter.new.log(:warn, "Formatter failed: #{e.message}. Using fallback formatter.")
            fallback_formatter.call(level, env, message, metadata)
          end
        end

        # Delegate log message to registered adapters with environment-aware filtering and rate-limited warnings
        # @param level [Symbol] log level (:info, :warn, :error, :debug)
        # @param message [String] the message to log
        # @param metadata [Hash, nil] optional structured metadata
        def delegate_log(level, message, metadata = nil)
          # Early return if message doesn't meet level threshold
          return false unless should_log?(level)

          ensure_initialized
          formatted_message = format_message(level, message, metadata)

          # Capture adapters with minimal lock time
          current_adapters = nil
          @mutex.synchronize { current_adapters = @adapters.dup }

          # Try each adapter without holding the main lock (no quarantine - all adapters always tried)
          success = false
          current_adapters.each do |adapter|
            if adapter.log(level, formatted_message)
              update_adapter_health(adapter, true)
              success = true
              break # Return on first successful adapter
            else
              update_adapter_health(adapter, false)
              # Call warning handler and emit rate-limited warning for repeated failures
              failure_message = "Adapter #{adapter.class} failed to log message"
              call_warning_handler(adapter, nil, failure_message)
              StdoutAdapter.new.log(:warn, failure_message) if should_warn_for_adapter?(adapter)
            end
          rescue StandardError => e
            update_adapter_health(adapter, false, e)
            # Call warning handler and emit rate-limited warning for adapter exceptions
            failure_message = "Adapter #{adapter.class} failed: #{e.message}"
            call_warning_handler(adapter, e, failure_message)
            StdoutAdapter.new.log(:warn, failure_message) if should_warn_for_adapter?(adapter)
          end

          # Fallback if no adapter succeeded
          unless success
            output_stream = level == :error ? $stderr : $stdout
            output_stream.puts formatted_message
            success = true
          end

          success
        end
      end
    end
  end
end
