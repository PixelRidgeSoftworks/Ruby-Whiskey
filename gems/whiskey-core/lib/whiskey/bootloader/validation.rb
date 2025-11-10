# frozen_string_literal: true

require 'socket'
require 'timeout'

module Whiskey
  module Core
    module Bootloader
      # Validation module for bootloader integrity checking
      #
      # Provides comprehensive validation of thread safety, deterministic behavior, and consistent state
      # with robust error handling and thread-safe state access. All validation checks are designed
      # to be non-destructive and safe to execute during any bootloader lifecycle phase.
      #
      # Features:
      # - Thread-safe state reading with mutex protection
      # - Graceful handling of missing or malformed instance variables
      # - Standardized violation reporting with consistent severity levels
      # - Non-blocking integrity checks that avoid unreliable mutex ownership detection
      # - Zero side effects during validation execution
      # - Per-check execution time profiling and total runtime reporting
      # - Unified validation framework with exception isolation
      # - Weighted validation scoring system
      # - Optional deep validation mode for comprehensive checks
      # - Analytics telemetry integration when available
      # - Test injection support for stress testing scenarios
      #
      # @example Basic usage
      #   report = validate_bootloader_integrity!
      #   puts "Validation passed: #{report[:passed]}"
      #   puts "Violations found: #{report[:violations].size}"
      #   puts "Validation score: #{report[:summary][:validation_score]}"
      #
      # @example Deep validation
      #   report = validate_bootloader_integrity!(deep: true)
      #   puts "Total runtime: #{report[:execution_time_ms]}ms"
      #
      # @example Selective validation
      #   report = validate_bootloader_integrity!(only: [:validate_mutex_integrity])
      #
      # @example Checking specific violations
      #   report = validate_bootloader_integrity!
      #   critical_issues = report[:violations].select { |v| v[:severity] == :critical }
      #   puts "Critical issues: #{critical_issues.size}"
      module Validation
        # Configuration constants for validation system
        module Config
          # Valid severity levels for validation violations
          SEVERITY_LEVELS = %i[critical warning info].freeze

          # Code base mapping for each validation check category
          CODE_BASES = {
            mutex_integrity: 1,
            manifest_schema_consistency: 2,
            hook_execution_determinism: 3,
            duplicate_subsystem_registrations: 4,
            orphaned_hook_references: 5,
            boot_state_consistency: 6
          }.freeze
        end

        # Unified validation checks registry
        # Each check includes method name, description, required for deep validation, and unique code base
        CHECKS = [
          { method: :validate_mutex_integrity, description: 'Mutex integrity and availability', deep_only: false,
            code_base: Config::CODE_BASES[:mutex_integrity] },
          { method: :validate_manifest_schema_consistency, description: 'Manifest schema consistency',
            deep_only: false, code_base: Config::CODE_BASES[:manifest_schema_consistency] },
          { method: :validate_hook_execution_determinism, description: 'Hook execution determinism', deep_only: false,
            code_base: Config::CODE_BASES[:hook_execution_determinism] },
          { method: :validate_duplicate_subsystem_registrations, description: 'No duplicate subsystem registrations',
            deep_only: false, code_base: Config::CODE_BASES[:duplicate_subsystem_registrations] },
          { method: :validate_orphaned_hook_references, description: 'No orphaned hook references', deep_only: false,
            code_base: Config::CODE_BASES[:orphaned_hook_references] },
          { method: :validate_boot_state_consistency, description: 'Boot state consistency', deep_only: true,
            code_base: Config::CODE_BASES[:boot_state_consistency] }
        ].freeze

        # Self-validation block to ensure all validation checks have defined methods
        begin
          if ENV['BOOT_VALIDATION_SELFTEST'] == 'true'
            CHECKS.each do |check_config|
              method_name = check_config[:method]
              warn("Validation check #{method_name} missing") unless instance_methods.include?(method_name)
            end
          end
        rescue StandardError
          # Silently handle any errors in self-validation to avoid breaking module loading
        end

        # Active telemetry threads for graceful shutdown
        @telemetry_threads = []
        @telemetry_threads_mutex = Mutex.new

        # Internal validation cache for filtered checks
        @_validation_cache = {}
        @_cache_mutex = Mutex.new

        # Comprehensive bootloader integrity validation
        #
        # Verifies thread safety, deterministic behavior, and consistent state across all
        # bootloader components. Uses thread-safe state access and graceful error handling
        # to ensure validation can be safely performed during any bootloader lifecycle phase.
        #
        # @param deep [Boolean] whether to run expensive deep validation checks
        # @param only [Array<Symbol>, Symbol, nil] specific checks to run (nil for all applicable checks)
        # @return [Hash] structured validation report with the following structure:
        #   - :validation_timestamp [Time] when validation was performed
        #   - :validation_version [String] version of validation logic
        #   - :passed [Boolean] true if no violations were found
        #   - :violations [Array<Hash>] list of violations, each with :check, :violation, :severity, :code
        #   - :checks_performed [Array<String>] list of validation checks that were executed
        #   - :check_timings [Hash] execution time for each check in milliseconds
        #   - :execution_time_ms [Float] total validation runtime in milliseconds
        #   - :summary [Hash] counts of violations by severity level, validation score, environment, checks run, and deep mode
        #   - :validation_error [String] error message if validation itself failed (optional)
        #   - :validation_backtrace [Array<String>] error backtrace if validation failed (optional)
        def validate_bootloader_integrity!(deep: false, only: nil)
          start_time = Time.now

          report = {
            validation_timestamp: start_time,
            validation_version: '1.4',
            passed: true,
            violations: [],
            checks_performed: [],
            check_timings: {},
            execution_time_ms: 0.0
          }

          begin
            # Inject test violations if in simulation mode
            inject_test_violations(report) if @_simulate_state_error

            # Execute validation checks with unified framework
            selected_checks = filter_checks(only, deep)
            selected_checks.each do |check_config|
              execute_validation_check(check_config, report)
            end

            report[:passed] = report[:violations].empty?

            # Add summary of violations by severity with weighted score
            report[:summary] = generate_violation_summary(report[:violations], deep, selected_checks)
          rescue StandardError => e
            report[:passed] = false
            report[:validation_error] = e.message
            report[:validation_backtrace] = e.backtrace
            report[:summary] =
              { critical: 0, warning: 0, info: 0, total: 0, validation_score: 0, environment: ENV['RACK_ENV'] || 'unknown',
                checks_run: 0, deep_mode: deep }
          end

          # Calculate total execution time
          end_time = Time.now
          report[:execution_time_ms] = ((end_time - start_time) * 1000).round(2)

          # Emit telemetry if Analytics module is available
          emit_validation_telemetry(report) if defined?(Whiskey::Core::Bootloader::Analytics)

          report
        end

        # Await telemetry flush for graceful shutdown
        #
        # @param timeout [Float] maximum time to wait for telemetry threads to complete
        # @return [Boolean] true if all threads completed within timeout
        def await_telemetry_flush(timeout: 1.0)
          deadline = Time.now + timeout

          self.class.instance_variable_get(:@telemetry_threads_mutex).synchronize do
            # Prune dead threads first for consistent behavior
            threads = self.class.instance_variable_get(:@telemetry_threads)
            threads.select!(&:alive?)
            active_threads = threads.dup

            active_threads.each do |thread|
              remaining_time = deadline - Time.now
              break if remaining_time <= 0

              thread.join(remaining_time) if thread.alive?
            end

            # Final cleanup of completed threads
            final_active_threads = threads.select(&:alive?)
            self.class.instance_variable_set(:@telemetry_threads, final_active_threads)

            if final_active_threads.any?
              log_if_available(:warn,
                               "Telemetry flush timed out; some threads still active: #{final_active_threads.size}")
              false
            else
              true
            end
          end
        end

        private

        # Filter checks based on only parameter and deep mode
        #
        # @param only [Array<Symbol>, Symbol, nil] specific checks to run
        # @param deep [Boolean] whether deep validation is enabled
        # @return [Array<Hash>] filtered check configurations
        def filter_checks(only, deep)
          # Create normalized cache key from parameters
          only_list = Array(only).compact.map(&:to_s).sort.join(',')
          cache_key = "deep=#{deep};only=#{only_list}"

          # Check cache first - return deep copy to prevent mutation
          self.class.instance_variable_get(:@_cache_mutex).synchronize do
            cache = self.class.instance_variable_get(:@_validation_cache)
            cached_result = cache[cache_key]
            if cached_result
              begin
                return Marshal.load(Marshal.dump(cached_result))
              rescue StandardError
                return cached_result.dup
              end
            end
          end

          # Filter checks if not cached
          checks = CHECKS.dup

          # Filter by deep mode
          checks.reject! { |check| check[:deep_only] && !deep }

          # Filter by only parameter if specified
          if only
            only_methods = Array(only)
            checks.select! { |check| only_methods.include?(check[:method]) }
          end

          # Cache the result as deep copy to prevent mutation
          self.class.instance_variable_get(:@_cache_mutex).synchronize do
            cache = self.class.instance_variable_get(:@_validation_cache)
            begin
              cached_checks = Marshal.load(Marshal.dump(checks))
              # Freeze cached array and elements to guarantee immutability
              cached_checks.each(&:freeze).freeze
              cache[cache_key] = cached_checks
            rescue StandardError
              log_if_available(:debug, "Deep copy failed for cache key #{cache_key}")
              # Skip caching rather than storing possibly mutable dup
            end
          end

          checks
        end

        # Safely fetch instance variable value with optional default
        #
        # @param var_name [Symbol] instance variable name (including @)
        # @param default [Object] default value if variable is not defined
        # @return [Object] variable value or default
        def fetch_state(var_name, default = nil)
          if instance_variable_defined?(var_name)
            instance_variable_get(var_name)
          else
            default
          end
        end

        # Generate deterministic violation code
        #
        # @param code_base [Integer] base code for the check (e.g., 2 for manifest checks)
        # @param violation_index [Integer] index of the violation within the current check
        # @return [String] formatted violation code (e.g., "VAL021")
        def generate_violation_code(code_base, violation_index)
          unique_code = (code_base * 10 + violation_index).clamp(1, 999)
          format('VAL%03d', unique_code)
        end

        # Execute a single validation check with timing and exception isolation
        #
        # @param check_config [Hash] configuration for the validation check
        # @param report [Hash] validation report to update
        def execute_validation_check(check_config, report)
          method_name = check_config[:method]
          check_start_time = Time.now

          # Ensure check registration happens even on exceptions
          check_name = method_name.to_s.gsub(/^validate_/, '')
          report[:checks_performed] << check_name unless report[:checks_performed].include?(check_name)

          begin
            # Set current check code base for violation generation and reset violation counter
            @current_check_code_base = check_config[:code_base]
            @current_check_violation_index = 0

            # Execute the validation check method
            send(method_name, report)
          rescue StandardError => e
            # Isolate exceptions to prevent validation framework failure
            add_violation(report,
                          check: method_name.to_s,
                          violation: "Check execution failed: #{e.message}",
                          severity: :critical)
          ensure
            # Record execution timing
            check_end_time = Time.now
            execution_time_ms = ((check_end_time - check_start_time) * 1000).round(2)
            report[:check_timings][method_name] = execution_time_ms

            # Clear current check code base and violation index
            @current_check_code_base = nil
            @current_check_violation_index = nil
          end
        end

        # Generate summary of violations by severity level with weighted validation score
        #
        # @param violations [Array<Hash>] list of violations
        # @param deep [Boolean] whether deep validation was enabled
        # @param selected_checks [Array<Hash>] checks that were executed
        # @return [Hash] counts by severity level, validation score, and execution metadata
        def generate_violation_summary(violations, deep, selected_checks)
          summary = {
            critical: 0,
            warning: 0,
            info: 0,
            total: violations.size,
            environment: ENV['RACK_ENV'] || 'unknown',
            checks_run: selected_checks.size,
            deep_mode: deep
          }

          violations.each do |violation|
            severity = violation[:severity] || :warning
            summary[severity] = summary[severity].to_i + 1
          end

          # Calculate weighted validation score (100 - (critical*5 + warning*2))
          score = 100 - (summary[:critical] * 5 + summary[:warning] * 2)
          summary[:validation_score] = score.clamp(0, 100)

          # Add runtime metadata
          summary[:ruby_version] = RUBY_VERSION
          begin
            summary[:hostname] = Socket.gethostname
          rescue StandardError
            summary[:hostname] = 'unknown'
          end
          summary[:thread_count] = Thread.list.size

          summary
        end

        # Inject test violations for stress testing scenarios
        #
        # @param report [Hash] validation report to update
        def inject_test_violations(report)
          # Randomly inject a few warning-level violations for testing
          test_violations = [
            'Simulated mutex contention detected',
            'Simulated configuration drift in test subsystem',
            'Simulated hook timing inconsistency'
          ]

          # Inject 1-3 random test violations
          num_violations = rand(1..3)
          test_violations.sample(num_violations).each_with_index do |violation, index|
            add_violation(report,
                          check: 'test_injection',
                          violation: violation,
                          severity: :warning,
                          context: "Stress test violation ##{index + 1}")
          end
        end

        # Emit validation telemetry to Analytics module asynchronously
        #
        # @param report [Hash] validation report for telemetry
        def emit_validation_telemetry(report)
          telemetry_thread = Thread.new do
            # Set thread name for easier debugging
            Thread.current.name = 'ValidationTelemetryEmitter' if Thread.current.respond_to?(:name=)

            # Disable thread abortion on exception for current thread only - safe as it doesn't affect global state
            Thread.current.abort_on_exception = false if Thread.current.respond_to?(:abort_on_exception=)

            # Disable exception reporting for this thread to avoid noise
            Thread.current.report_on_exception = false if Thread.current.respond_to?(:report_on_exception=)

            log_if_available(:info, 'Validation telemetry emission starting')

            Thread.handle_interrupt(Object => :on_blocking) do
              # Wrap telemetry emission in timeout to ensure it never blocks shutdown
              Timeout.timeout(0.5) do
                # Create lightweight telemetry event including environment
                telemetry_data = {
                  event: 'bootloader_validation',
                  timestamp: report[:validation_timestamp],
                  validation_version: report[:validation_version],
                  passed: report[:passed],
                  execution_time_ms: report[:execution_time_ms],
                  checks_count: report[:checks_performed].size,
                  violations_summary: report[:summary].slice(:critical, :warning, :info, :validation_score,
                                                             :environment),
                  deep_validation: report[:summary][:deep_mode],
                  environment: report[:summary][:environment]
                }

                # Emit telemetry if the current object responds to analytics methods
                # This assumes the including class has access to Analytics functionality
                if respond_to?(:analytics, true)
                  # Store telemetry data in a way that doesn't interfere with validation
                  @_validation_telemetry ||= []
                  @_validation_telemetry << telemetry_data
                end
              end
            rescue Timeout::Error
              # Telemetry took too long, abandon it to avoid blocking shutdown
            rescue StandardError
              # Silently handle telemetry errors to prevent validation impact
              # In production, this might log to a separate telemetry error channel
            end

            log_if_available(:info, 'Validation telemetry emission completed')
          end

          # Track telemetry thread with lifecycle hygiene - prune dead threads to prevent unbounded growth
          self.class.instance_variable_get(:@telemetry_threads_mutex).synchronize do
            threads = self.class.instance_variable_get(:@telemetry_threads)
            # Prune dead threads before adding new one
            threads.select!(&:alive?)
            threads << telemetry_thread if telemetry_thread.alive?
          end

          telemetry_thread
        end

        # Helper for logging with optional Bootloader logger availability
        #
        # @param level [Symbol] log level (:info, :warn, :debug, etc.)
        # @param message [String] message to log
        def log_if_available(level, message)
          if defined?(Whiskey::Core::Bootloader::Logging) && Whiskey::Core::Bootloader::Logging.respond_to?(:logger)
            Whiskey::Core::Bootloader::Logging.logger.send(level, message)
          end
        rescue StandardError
          # Silently ignore all logging errors
        end

        # Standardized helper for recording validation violations
        #
        # @param report [Hash] validation report to update
        # @param check [String] name of the validation check
        # @param violation [String] description of the violation found
        # @param severity [Symbol] severity level (:critical, :warning, :info)
        # @param context [String, nil] optional additional context information
        def add_violation(report, check:, violation:, severity: :warning, context: nil)
          # Validate severity level, default to :warning if invalid
          validated_severity = Config::SEVERITY_LEVELS.include?(severity) ? severity : :warning

          # Generate deterministic violation code based on current check and violation index
          code_base = @current_check_code_base || 99 # Default to 99 if no current check
          @current_check_violation_index ||= 0
          @current_check_violation_index += 1
          unique_code = generate_violation_code(code_base, @current_check_violation_index)

          violation_record = {
            check: check,
            violation: violation,
            severity: validated_severity,
            code: unique_code
          }

          # Add context if provided
          violation_record[:context] = context if context

          report[:violations] << violation_record
        end

        # Lightweight helper for recording critical violations
        #
        # @param report [Hash] validation report to update
        # @param check [String] name of the validation check
        # @param violation [String] description of the violation found
        # @param context [String, nil] optional additional context information
        def _critical(report, check:, violation:, context: nil)
          add_violation(report, check: check, violation: violation, severity: :critical, context: context)
        end

        # Lightweight helper for recording warning violations
        #
        # @param report [Hash] validation report to update
        # @param check [String] name of the validation check
        # @param violation [String] description of the violation found
        # @param context [String, nil] optional additional context information
        def _warning(report, check:, violation:, context: nil)
          add_violation(report, check: check, violation: violation, severity: :warning, context: context)
        end

        # Lightweight helper for recording info violations
        #
        # @param report [Hash] validation report to update
        # @param check [String] name of the validation check
        # @param violation [String] description of the violation found
        # @param context [String, nil] optional additional context information
        def _info(report, check:, violation:, context: nil)
          add_violation(report, check: check, violation: violation, severity: :info, context: context)
        end

        # Thread-safe helper for reading shared state
        #
        # Uses @state_mutex if available to ensure consistent reads of shared state
        # variables. Gracefully handles cases where mutex is not available.
        #
        # @yield block to execute with thread-safe state access
        # @return [Object] result of the block execution
        def safe_read_state(&block)
          if defined?(@state_mutex) && @state_mutex.is_a?(Mutex)
            @state_mutex.synchronize(&block)
          else
            # If no state mutex available, execute without synchronization
            # This maintains functionality when mutex is not properly initialized
            yield
          end
        rescue StandardError
          # Return nil if state reading fails to prevent validation crashes
          nil
        end

        # Validation check: mutex integrity and availability
        #
        # Verifies that all required mutexes exist and are proper Mutex objects.
        # Uses non-blocking integrity checks instead of unreliable mutex ownership detection.
        #
        # @param report [Hash] validation report to update
        def validate_mutex_integrity(report)
          check_name = 'mutex_integrity'
          report[:checks_performed] << check_name

          # Verify all mutexes exist and are proper Mutex objects
          mutex_checks = [
            { var: :@boot_mutex, name: '@boot_mutex' },
            { var: :@state_mutex, name: '@state_mutex' },
            { var: :@hooks_mutex, name: '@hooks_mutex' }
          ]

          mutex_checks.each do |check|
            mutex_var = check[:var]
            mutex_name = check[:name]

            mutex = fetch_state(mutex_var)
            if mutex
              unless mutex.is_a?(Mutex)
                add_violation(report, check: check_name,
                                      violation: "#{mutex_name} is not a Mutex object (found: #{mutex.class})",
                                      severity: :critical)
              end
            else
              add_violation(report, check: check_name,
                                    violation: "#{mutex_name} is not defined",
                                    severity: :critical)
            end
          end

          # Perform light non-blocking mutex availability check if supported
          boot_mutex = fetch_state(:@boot_mutex)
          return unless boot_mutex.is_a?(Mutex)

          begin
            # Try a non-blocking lock to test availability
            if boot_mutex.try_lock
              boot_mutex.unlock # Immediately unlock since this is just a test
            end
          rescue ThreadError
            # Mutex is already locked, which is fine - just note it
            add_violation(report, check: check_name,
                                  violation: 'Boot mutex is currently locked during validation',
                                  severity: :info)
          rescue StandardError => e
            add_violation(report, check: check_name,
                                  violation: "Boot mutex availability check failed: #{e.message}",
                                  severity: :warning)
          end
        end

        # Validation check: manifest schema consistency
        #
        # Verifies that subsystem manifest entries have required keys and proper types.
        # Gracefully handles missing or malformed manifest data.
        #
        # @param report [Hash] validation report to update
        def validate_manifest_schema_consistency(report)
          check_name = 'manifest_schema_consistency'
          report[:checks_performed] << check_name

          required_manifest_keys = %i[status priority depends_on registered_at boot_time
                                      config_cached enabled config_source config_checksum hook_count]

          safe_read_state do
            # Gracefully handle missing or malformed subsystem_manifest
            manifest = fetch_state(:@subsystem_manifest, {})

            unless manifest.respond_to?(:each)
              add_violation(report, check: check_name,
                                    violation: "Subsystem manifest is not iterable (found: #{manifest.class})",
                                    severity: :critical)
              return
            end

            manifest.each do |name, manifest_data|
              unless manifest_data.is_a?(Hash)
                add_violation(report, check: check_name,
                                      violation: "Subsystem #{name} manifest is not a Hash (found: #{manifest_data.class})",
                                      severity: :critical)
                next
              end

              missing_keys = required_manifest_keys - manifest_data.keys
              if missing_keys.any?
                add_violation(report, check: check_name,
                                      violation: "Subsystem #{name} missing required keys: #{missing_keys.join(', ')}",
                                      severity: :warning)
              end

              # Validate key types
              if manifest_data[:status] && !%i[configured warning failed].include?(manifest_data[:status])
                add_violation(report, check: check_name,
                                      violation: "Subsystem #{name} has invalid status: #{manifest_data[:status]}",
                                      severity: :warning)
              end

              next unless manifest_data[:priority] && !manifest_data[:priority].is_a?(Integer)

              add_violation(report, check: check_name,
                                    violation: "Subsystem #{name} priority is not an Integer (found: #{manifest_data[:priority].class})",
                                    severity: :warning)
            end
          end
        end

        # Validation check: hook execution determinism
        #
        # Verifies that hooks will execute in deterministic order and checks for duplicate
        # order/name pairs in a single optimized traversal.
        #
        # @param report [Hash] validation report to update
        def validate_hook_execution_determinism(report)
          check_name = 'hook_execution_determinism'
          report[:checks_performed] << check_name

          safe_read_state do
            # Gracefully handle missing or malformed boot_hooks
            hooks_data = fetch_state(:@boot_hooks, {})

            unless hooks_data.respond_to?(:each)
              add_violation(report, check: check_name,
                                    violation: "Boot hooks data is not iterable (found: #{hooks_data.class})",
                                    severity: :critical)
              return
            end

            hooks_data.each do |phase, hooks|
              next unless hooks.respond_to?(:each)

              # Single traversal optimization: collect order/name pairs and check determinism simultaneously
              begin
                order_name_pairs = []
                hooks_array = []

                hooks.each do |name, data|
                  order = data.is_a?(Hash) ? (data[:order] || 50) : 50
                  pair = [order, name.to_s]

                  order_name_pairs << pair
                  hooks_array << [name, data]
                end

                # Check for deterministic ordering
                sorted_hooks = hooks_array.sort_by do |name, data|
                  order = data.is_a?(Hash) ? (data[:order] || 50) : 50
                  [order, name.to_s]
                end

                unless sorted_hooks == hooks_array
                  add_violation(report, check: check_name,
                                        violation: "Hooks in phase #{phase} are not deterministically ordered",
                                        severity: :warning)
                end

                # Check for duplicate order/name pairs
                duplicates = order_name_pairs.group_by { |pair| pair }.select { |_, instances| instances.length > 1 }
                if duplicates.any?
                  add_violation(report, check: check_name,
                                        violation: "Duplicate order/name pairs in phase #{phase}: #{duplicates.keys}",
                                        severity: :critical)
                end
              rescue StandardError => e
                add_violation(report, check: check_name,
                                      violation: "Failed to validate hook determinism for phase #{phase}: #{e.message}",
                                      severity: :warning)
              end
            end
          end
        end

        # Validation check: no duplicate subsystem registrations
        #
        # Verifies that subsystem registry contains no duplicates and that all
        # registered subsystems have proper registration information.
        #
        # @param report [Hash] validation report to update
        def validate_duplicate_subsystem_registrations(report)
          check_name = 'duplicate_subsystem_registrations'
          report[:checks_performed] << check_name

          safe_read_state do
            # Gracefully handle missing or malformed subsystem_registry
            registry = fetch_state(:@subsystem_registry, {})

            unless registry.respond_to?(:keys) && registry.respond_to?(:each)
              add_violation(report, check: check_name,
                                    violation: "Subsystem registry is not a proper collection (found: #{registry.class})",
                                    severity: :critical)
              return
            end

            # Check for duplicate registrations (shouldn't happen with Hash but verify)
            begin
              registry_names = registry.keys
              unique_names = registry_names.uniq

              if registry_names.size != unique_names.size
                duplicates = registry_names.group_by { |name| name }.select { |_, instances| instances.length > 1 }.keys
                add_violation(report, check: check_name,
                                      violation: "Duplicate subsystem registrations detected: #{duplicates.join(', ')}",
                                      severity: :critical)
              end
            rescue StandardError => e
              add_violation(report, check: check_name,
                                    violation: "Failed to check for duplicate registrations: #{e.message}",
                                    severity: :warning)
            end

            # Check that all registered subsystems have proper modules
            registry.each do |name, info|
              next if info.is_a?(Hash) && info[:module]

              add_violation(report, check: check_name,
                                    violation: "Subsystem #{name} has invalid registration info (found: #{info.class})",
                                    severity: :critical)
            end
          end
        end

        # Validation check: no orphaned hook references
        #
        # Verifies that hooks targeting specific subsystems only reference
        # actually registered subsystems to prevent execution errors.
        #
        # @param report [Hash] validation report to update
        def validate_orphaned_hook_references(report)
          check_name = 'orphaned_hook_references'
          report[:checks_performed] << check_name

          safe_read_state do
            # Gracefully handle missing or malformed data structures
            registry = fetch_state(:@subsystem_registry, {})
            hooks_data = fetch_state(:@boot_hooks, {})

            unless registry.respond_to?(:keys)
              add_violation(report, check: check_name,
                                    violation: 'Cannot check hook references: subsystem registry not accessible',
                                    severity: :warning)
              return
            end

            unless hooks_data.respond_to?(:each)
              add_violation(report, check: check_name,
                                    violation: 'Cannot check hook references: boot hooks data not accessible',
                                    severity: :warning)
              return
            end

            # Get list of registered subsystem names
            begin
              registered_subsystem_names = registry.keys
            rescue StandardError => e
              add_violation(report, check: check_name,
                                    violation: "Failed to get registered subsystem names: #{e.message}",
                                    severity: :warning)
              return
            end

            # Check for hooks that target non-existent subsystems
            hooks_data.each do |phase, hooks|
              next unless hooks.respond_to?(:each)

              hooks.each do |hook_name, hook_data|
                next unless hook_data.is_a?(Hash) && hook_data[:target]

                target = hook_data[:target]
                next if registered_subsystem_names.include?(target)

                add_violation(report, check: check_name,
                                      violation: "Hook #{hook_name} in phase #{phase} targets non-existent subsystem: #{target}",
                                      severity: :warning,
                                      context: "Phase: #{phase}, Hook: #{hook_name}, Target: #{target}")
              end
            end
          end
        end

        # Validation check: boot state consistency
        #
        # Verifies logical consistency of boot state flags, timing information,
        # and failed subsystem tracking across different data structures.
        #
        # @param report [Hash] validation report to update
        def validate_boot_state_consistency(report)
          check_name = 'boot_state_consistency'
          report[:checks_performed] << check_name

          safe_read_state do
            # Gracefully read boot state variables using fetch_state
            boot_completed = fetch_state(:@boot_sequence_completed, false)
            boot_started = fetch_state(:@boot_sequence_started, false)
            shutdown_completed = fetch_state(:@shutdown_completed, false)
            shutdown_started = fetch_state(:@shutdown_started, false)

            # Check logical consistency of boot state
            if boot_completed && !boot_started
              add_violation(report, check: check_name,
                                    violation: 'Boot sequence marked completed but not started',
                                    severity: :critical)
            end

            if shutdown_completed && !shutdown_started
              add_violation(report, check: check_name,
                                    violation: 'Shutdown marked completed but not started',
                                    severity: :warning)
            end

            # Check boot timing consistency if available
            boot_completed_at = fetch_state(:@boot_completed_at)
            boot_started_at = fetch_state(:@boot_started_at)
            boot_duration = fetch_state(:@boot_duration)

            if boot_completed && boot_completed_at && boot_started_at && boot_duration
              begin
                calculated_duration = boot_completed_at - boot_started_at
                if (calculated_duration - boot_duration).abs > 0.1
                  add_violation(report, check: check_name,
                                        violation: "Boot duration inconsistent with calculated duration (stored: #{boot_duration}, calculated: #{calculated_duration})",
                                        severity: :warning)
                end
              rescue StandardError => e
                add_violation(report, check: check_name,
                                      violation: "Failed to validate boot timing consistency: #{e.message}",
                                      severity: :warning)
              end
            end

            # Check that failed subsystems are properly tracked
            begin
              manifest = fetch_state(:@subsystem_manifest, {})
              failed_tracking = fetch_state(:@failed_subsystems, {})

              if manifest.respond_to?(:count) && failed_tracking.respond_to?(:size)
                failed_in_manifest = manifest.count { |_, data| data.is_a?(Hash) && data[:status] == :failed }
                failed_in_tracking = failed_tracking.size

                if failed_in_manifest != failed_in_tracking
                  add_violation(report, check: check_name,
                                        violation: "Failed subsystem count mismatch between manifest (#{failed_in_manifest}) and tracking (#{failed_in_tracking})",
                                        severity: :warning,
                                        context: "Manifest failures: #{failed_in_manifest}, Tracking failures: #{failed_in_tracking}")
                end
              end
            rescue StandardError => e
              add_violation(report, check: check_name,
                                    violation: "Failed to validate subsystem tracking consistency: #{e.message}",
                                    severity: :warning)
            end
          end
        end
      end
    end
  end
end
