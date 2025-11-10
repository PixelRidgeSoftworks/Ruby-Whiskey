# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Diagnostics module for comprehensive system health reporting
      # Provides self-diagnostics and health monitoring capabilities
      module Diagnostics
        # Comprehensive self-diagnostics report combining all validation data
        # @return [Hash] complete diagnostic summary with deterministic hash signature
        def self_diagnostics_report
          # Gather all diagnostic data
          diagnostic_data = {
            report_timestamp: Time.now,
            report_version: '1.0',
            bootloader_version: version_info,

            # Core diagnostics
            boot_status: boot_status,
            diagnostics: diagnostics,

            # Enhanced manifest with digest
            manifest: manifest,

            # Validation results (cached or fresh)
            integrity_validation: get_cached_validation_or_run,

            # Stress test history
            stress_test_history: @stress_test_log.dup,

            # Thread safety indicators
            thread_safety_indicators: {
              mutex_count: [@boot_mutex, @state_mutex, @hooks_mutex].count { |m| m.is_a?(Mutex) },
              current_thread_holding_boot_mutex: @boot_mutex.owned?,
              hook_execution_tracking: !@hook_execution_states.empty?
            },

            # Hook system health
            hook_system_health: analyze_hook_system_health
          }

          # Generate deterministic signature for consistency verification
          signature_data = [
            diagnostic_data[:bootloader_version][:bootloader_version],
            diagnostic_data[:manifest][:manifest_version],
            diagnostic_data[:manifest][:digest],
            @subsystem_registry.keys.sort.join(',')
          ].join('|')

          diagnostic_data[:deterministic_signature] = Digest::SHA256.hexdigest(signature_data)
          diagnostic_data
        end

        # Version information for external tools and diagnostics
        # @return [Hash] comprehensive version and schema information
        def self.version_info
          {
            bootloader_version: defined?(Whiskey::Core::Bootloader::VERSION) ? Whiskey::Core::Bootloader::VERSION : 'unknown',
            manifest_version: defined?(Whiskey::Core::Bootloader::Core::MANIFEST_VERSION) ? Whiskey::Core::Bootloader::Core::MANIFEST_VERSION : '2.0',
            framework_version: defined?(Whiskey::Core::VERSION) ? Whiskey::Core::VERSION : 'unknown',
            schema_digest: Digest::SHA256.hexdigest('2.0:bootloader_core'),
            ruby_version: RUBY_VERSION,
            generated_at: Time.now
          }
        end

        # Instance method for version info access
        def version_info
          self.class.version_info
        end

        private

        # Get cached validation results or run fresh validation
        # @return [Hash] validation results
        def get_cached_validation_or_run
          cache_key = "integrity_validation_#{Time.now.strftime('%Y%m%d%H')}" # Hourly cache

          if @validation_cache[cache_key] &&
             @validation_cache[cache_key][:validation_timestamp] > Time.now - 3600 # 1 hour
            @validation_cache[cache_key]
          else
            fresh_validation = validate_bootloader_integrity!
            @validation_cache[cache_key] = fresh_validation
            @validation_cache = @validation_cache.to_a.last(24).to_h # Keep 24 hours of cache
            fresh_validation
          end
        end

        # Analyze hook system health for diagnostics
        # @return [Hash] hook system health metrics
        def analyze_hook_system_health
          {
            total_hooks: @boot_hooks.values.sum(&:size),
            hooks_by_phase: @boot_hooks.transform_values(&:size),
            hooks_with_targets: @boot_hooks.values.sum do |hooks|
              hooks.count { |_, data| data.is_a?(Hash) && data[:target] }
            end,
            hook_execution_failures: @hook_execution_states.count { |_, state| state[:failed_at] },
            average_hook_execution_time: calculate_average_hook_execution_time,
            deterministic_ordering: hooks_have_deterministic_ordering?
          }
        end

        # Calculate average hook execution time from tracked states
        # @return [Float] average execution time in seconds
        def calculate_average_hook_execution_time
          completed_hooks = @hook_execution_states.select { |_, state| state[:completed_at] && state[:started_at] }
          return 0.0 if completed_hooks.empty?

          total_time = completed_hooks.sum { |_, state| state[:completed_at] - state[:started_at] }
          total_time / completed_hooks.size
        end

        # Check if hooks have deterministic ordering
        # @return [Boolean] true if hook ordering is deterministic
        def hooks_have_deterministic_ordering?
          @boot_hooks.all? do |_phase, hooks|
            sorted_hooks = hooks.sort_by do |name, data|
              order = data.is_a?(Hash) ? (data[:order] || 50) : 50
              [order, name.to_s]
            end
            sorted_hooks == hooks.to_a
          end
        end
      end
    end
  end
end
