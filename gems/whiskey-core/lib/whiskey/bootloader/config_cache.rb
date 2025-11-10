# frozen_string_literal: true

require 'digest'

module Whiskey
  module Core
    module Bootloader
      # Fault-tolerant configuration caching with metadata and namespace support
      #
      # Enhanced to provide introspection, validation, and improved error handling
      # while maintaining full backward compatibility with existing API
      class ConfigCache
        # Internal cache structure: { key => { config: Hash, metadata: { timestamp: Time, digest: String } } }
        @cache = {}
        @cache_mutex = Mutex.new
        @default_namespace = nil

        # Exception class for configuration validation errors
        class ConfigValidationError < StandardError; end

        class << self
          # Get cached config for a subsystem
          #
          # @param name [Symbol, String] subsystem name
          # @param namespace [String, nil] optional namespace for namespaced caching
          # @return [Hash, nil] cached config or nil if not found or on error
          def get(name, namespace: nil)
            safe_mutex_operation do
              cache_key = build_cache_key(name, namespace)
              entry = @cache[cache_key]
              entry&.dig(:config)
            end
          end

          # Set cached config for a subsystem with validation and metadata
          #
          # @param name [Symbol, String] subsystem name
          # @param config [Hash, #to_h] config to cache (must be Hash-like)
          # @param namespace [String, nil] optional namespace for namespaced caching
          # @return [Boolean] true if successfully cached, false on validation error
          # @raise [ConfigValidationError] if config is not Hash-like (in strict mode)
          def set(name, config, namespace: nil)
            safe_mutex_operation do
              # Validate config is Hash-like
              validated_config = validate_config(config)
              return false unless validated_config

              cache_key = build_cache_key(name, namespace)
              frozen_config = validated_config.dup.freeze

              # Store config with metadata
              @cache[cache_key] = {
                config: frozen_config,
                metadata: {
                  timestamp: Time.now,
                  digest: calculate_config_digest(validated_config),
                  namespace: namespace,
                  original_name: name.to_s
                }
              }.freeze

              safe_log("Cached config for '#{cache_key}' (#{frozen_config.size} keys)", :debug)
              true
            end
          end

          # Get metadata for a cached configuration entry
          #
          # @param name [Symbol, String] subsystem name
          # @param namespace [String, nil] optional namespace
          # @return [Hash, nil] metadata hash with :timestamp, :digest, :namespace, :original_name or nil if not found
          def metadata(name, namespace: nil)
            safe_mutex_operation do
              cache_key = build_cache_key(name, namespace)
              entry = @cache[cache_key]
              entry&.dig(:metadata)&.dup # Return unfrozen copy for safety
            end
          end

          # Clear cache for a subsystem or all subsystems
          #
          # @param name [Symbol, String, nil] subsystem name, or nil for all
          # @param namespace [String, nil] optional namespace (only relevant when name is specified)
          # @return [Boolean] true if operation completed successfully
          def clear(name = nil, namespace: nil)
            safe_mutex_operation do
              if name
                cache_key = build_cache_key(name, namespace)
                removed = @cache.delete(cache_key)
                safe_log("Cleared cache for '#{cache_key}'#{removed ? '' : ' (not found)'}", :debug)
                !!removed
              else
                count = @cache.size
                @cache.clear
                safe_log("Cleared all cached configs (#{count} entries)", :info)
                true
              end
            end
          end

          # Get all cached subsystem names (keys)
          #
          # @param namespace [String, nil] optional namespace to filter by
          # @return [Array<String>] cached subsystem keys, optionally filtered by namespace
          def keys(namespace: nil)
            safe_mutex_operation do
              cache_keys = @cache.keys

              if namespace
                # Filter by namespace and extract original names
                prefix = "#{namespace}:"
                cache_keys.select { |key| key.to_s.start_with?(prefix) }
                          .map { |key| key.to_s.sub(prefix, '') }
              else
                # Return all keys, converting namespaced keys back to original format
                cache_keys.map do |key|
                  key_str = key.to_s
                  if key_str.include?(':')
                    # Return the full namespaced key for backward compatibility
                    key_str
                  else
                    key.to_s
                  end
                end
              end
            end
          end

          # Get comprehensive cache statistics and health information
          #
          # @return [Hash] cache statistics including entry count, total size, namespace breakdown
          def stats
            safe_mutex_operation do
              namespace_breakdown = {}
              total_configs = 0
              oldest_entry = nil
              newest_entry = nil

              @cache.each_value do |entry|
                metadata = entry[:metadata]
                namespace = metadata[:namespace] || 'default'

                namespace_breakdown[namespace] ||= 0
                namespace_breakdown[namespace] += 1
                total_configs += 1

                timestamp = metadata[:timestamp]
                oldest_entry = timestamp if !oldest_entry || timestamp < oldest_entry
                newest_entry = timestamp if !newest_entry || timestamp > newest_entry
              end

              {
                total_entries: total_configs,
                namespace_breakdown: namespace_breakdown,
                oldest_entry: oldest_entry,
                newest_entry: newest_entry,
                cache_health: total_configs.positive? ? 'active' : 'empty'
              }
            end
          end

          # Validate cache integrity and return detailed report
          #
          # @return [Hash] validation report with any integrity issues found
          def validate_integrity
            safe_mutex_operation do
              issues = []
              valid_entries = 0

              @cache.each do |key, entry|
                # Validate entry structure
                unless entry.is_a?(Hash) && entry.key?(:config) && entry.key?(:metadata)
                  issues << "Invalid entry structure for key: #{key}"
                  next
                end

                config = entry[:config]
                metadata = entry[:metadata]

                # Validate config is Hash-like
                unless config.respond_to?(:[]) && config.respond_to?(:keys)
                  issues << "Invalid config type for key: #{key} (#{config.class})"
                  next
                end

                # Validate metadata structure
                required_metadata = %i[timestamp digest original_name]
                missing_metadata = required_metadata - metadata.keys
                if missing_metadata.any?
                  issues << "Missing metadata for key: #{key} (#{missing_metadata.join(', ')})"
                  next
                end

                # Validate digest matches current config
                expected_digest = calculate_config_digest(config)
                if metadata[:digest] != expected_digest
                  issues << "Digest mismatch for key: #{key} (stored: #{metadata[:digest]}, calculated: #{expected_digest})"
                  next
                end

                valid_entries += 1
              rescue StandardError => e
                issues << "Validation error for key: #{key} - #{e.message}"
              end

              {
                total_entries: @cache.size,
                valid_entries: valid_entries,
                issues: issues,
                integrity_status: issues.empty? ? 'valid' : 'corrupted'
              }
            end
          end

          private

          # Build cache key with optional namespace support
          # @param name [Symbol, String] the base name
          # @param namespace [String, nil] optional namespace
          # @return [Symbol] the cache key
          def build_cache_key(name, namespace)
            if namespace && !namespace.to_s.empty?
              "#{namespace}:#{name}".to_sym
            else
              name.to_sym
            end
          end

          # Validate that config is Hash-like and convertible
          # @param config [Object] the config to validate
          # @return [Hash, nil] validated config hash or nil if invalid
          def validate_config(config)
            # Accept Hash or anything that responds to to_h
            if config.is_a?(Hash)
              config
            elsif config.respond_to?(:to_h)
              begin
                config.to_h
              rescue StandardError => e
                safe_log("Failed to convert config to hash: #{e.message}", :error)
                nil
              end
            else
              safe_log("Invalid config type: #{config.class} (expected Hash-like)", :error)
              nil
            end
          end

          # Calculate SHA256 digest of config for integrity checking
          # @param config [Hash] the config to digest
          # @return [String] hexadecimal digest
          def calculate_config_digest(config)
            # Convert config to a deterministic string representation for hashing
            config_string = config.sort.map { |k, v| "#{k}=#{v.inspect}" }.join('|')
            Digest::SHA256.hexdigest(config_string)
          end

          # Safe mutex operation wrapper with comprehensive error handling
          # @param block [Proc] the block to execute within mutex
          # @return [Object, nil] result of block execution or nil on error
          def safe_mutex_operation(&block)
            @cache_mutex.synchronize(&block)
          rescue StandardError => e
            safe_log("Cache operation failed: #{e.message}", :error)
            safe_log("Backtrace: #{e.backtrace.first(3).join('; ')}", :debug)
            nil
          end

          # Safe logging with fallback to stderr
          # @param message [String] message to log
          # @param level [Symbol] log level (:debug, :info, :warn, :error)
          def safe_log(message, level = :info)
            if defined?(Whiskey::Core::Log) && Whiskey::Core::Log.respond_to?(level)
              Whiskey::Core::Log.send(level, "[ConfigCache] #{message}")
            else
              # Fallback to stderr with level prefix
              prefix = case level
                       when :debug then '[DEBUG]'
                       when :info then '[INFO]'
                       when :warn then '[WARN]'
                       when :error then '[ERROR]'
                       else '[LOG]'
                       end
              warn "#{prefix} [ConfigCache] #{message}"
            end
          rescue StandardError => e
            # Ultimate fallback - bare stderr output
            warn "[CRITICAL] ConfigCache logging failed: #{e.message}"
            warn "[ConfigCache] #{message}"
          end
        end
      end
    end
  end
end
