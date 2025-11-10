# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Internal interface specifications for bootloader modules
      # Defines contracts, shared constants, and lifecycle expectations
      # Used for automated validation and maintenance consistency
      module Interfaces
        # Shared constants for cross-module consistency
        SHARED_MUTEX_NAMES = %i[@boot_mutex @state_mutex @hooks_mutex].freeze
        SHARED_STATE_KEYS = %i[@subsystem_registry @boot_hooks @boot_errors @boot_phases @hook_execution_states].freeze

        # Standard method naming patterns for consistency
        METHOD_PATTERNS = {
          registration: /^register_/,
          execution: /^execute_/,
          validation: /^validate_/,
          verification: /^verify_/,
          lifecycle: /^(boot_|shutdown_)/
        }.freeze

        # Module lifecycle phases (execution order)
        LIFECYCLE_PHASES = %i[
          initialization
          validation
          hook_registration
          subsystem_registration
          boot_sequence
          diagnostics
          production_safety
          stress_testing
        ].freeze

        # Mapping of module names to their corresponding contracts
        # Used for automated contract discovery and validation
        MODULE_CONTRACTS = {
          'HookManagement' => :HookManagementContract,
          'SubsystemManagement' => :SubsystemManagementContract,
          'BootSequence' => :BootSequenceContract,
          'Logging' => :LoggingContract,
          'Validation' => :ValidationContract,
          'StressTesting' => :StressTestingContract,
          'Diagnostics' => :DiagnosticsContract,
          'ProductionSafety' => :ProductionSafetyContract
        }.freeze

        # Declarative cross-module dependencies for automated validation
        # Format: { dependent_module => [required_modules_or_methods] }
        CROSS_DEPENDENCIES = {
          'HookManagement' => {
            state_variables: %i[@boot_hooks @hook_execution_states],
            methods: %i[safe_log_info safe_log_warn safe_log_error]
          },
          'SubsystemManagement' => {
            state_variables: %i[@subsystem_registry @subsystem_manifest @failed_subsystems],
            methods: %i[safe_log_info safe_log_warn safe_log_error]
          },
          'BootSequence' => {
            state_variables: %i[@boot_phases @subsystem_manifest @failed_subsystems @subsystem_registry],
            methods: %i[execute_boot_hooks cached_config cache_config update_boot_state safe_log_info safe_log_warn
                        safe_log_error]
          },
          'Logging' => {
            state_variables: %i[@state_mutex],
            methods: []
          }
        }.freeze

        # Interface contract for bootloader modules
        # Each included module should implement these guarantees
        module ModuleContract
          # Called after module inclusion to validate contract compliance
          # @param base [Class] the class including this module
          def self.extended(base)
            # Contract validation will be called by Core during initialization
          end

          # Required: Module initialization dependencies
          # @return [Array<Symbol>] list of shared state variables this module requires
          def required_state_variables
            []
          end

          # Required: Mutex dependencies for thread safety
          # @return [Array<Symbol>] list of mutexes this module uses
          def required_mutexes
            []
          end

          # Optional: Methods this module exposes for cross-module use
          # @return [Array<Symbol>] list of public methods
          def exposed_methods
            []
          end

          # Optional: Lifecycle phase this module operates in
          # @return [Symbol] phase from LIFECYCLE_PHASES
          def lifecycle_phase
            :initialization
          end
        end

        # Hook management interface contract
        module HookManagementContract
          extend ModuleContract

          def required_state_variables
            %i[@boot_hooks @hook_execution_states]
          end

          def required_mutexes
            %i[@hooks_mutex]
          end

          def exposed_methods
            %i[add_boot_hook remove_boot_hook execute_boot_hooks execute_validated_hooks]
          end

          def lifecycle_phase
            :hook_registration
          end
        end

        # Subsystem management interface contract
        module SubsystemManagementContract
          extend ModuleContract

          def required_state_variables
            %i[@subsystem_registry @subsystem_manifest @failed_subsystems]
          end

          def required_mutexes
            %i[@state_mutex]
          end

          def exposed_methods
            %i[register_subsystem unregister_subsystem registered_subsystems subsystem cached_config cache_config
               clear_config_cache]
          end

          def lifecycle_phase
            :subsystem_registration
          end
        end

        # Boot sequence interface contract
        module BootSequenceContract
          extend ModuleContract

          def required_state_variables
            %i[@boot_phases @subsystem_manifest @failed_subsystems]
          end

          def required_mutexes
            %i[@boot_mutex @state_mutex]
          end

          def exposed_methods
            %i[boot_subsystems verify_boot_integrity log_signature_summary]
          end

          def lifecycle_phase
            :boot_sequence
          end
        end

        # Logging interface contract
        module LoggingContract
          extend ModuleContract

          def required_state_variables
            %i[@state_mutex] # For update_boot_state helper
          end

          def required_mutexes
            %i[@state_mutex]
          end

          def exposed_methods
            %i[log_info log_warn log_error safe_log_info safe_log_warn safe_log_error update_boot_state colorize_log]
          end

          def lifecycle_phase
            :initialization
          end
        end

        # Validation interface contract
        module ValidationContract
          extend ModuleContract

          def required_state_variables
            %i[@validation_cache]
          end

          def required_mutexes
            %i[@state_mutex]
          end

          def lifecycle_phase
            :validation
          end
        end

        # Stress testing interface contract
        module StressTestingContract
          extend ModuleContract

          def required_state_variables
            %i[@stress_test_log]
          end

          def required_mutexes
            %i[@state_mutex]
          end

          def lifecycle_phase
            :stress_testing
          end
        end

        # Diagnostics interface contract
        module DiagnosticsContract
          extend ModuleContract

          def required_state_variables
            %i[@boot_phases @subsystem_manifest @boot_errors]
          end

          def required_mutexes
            %i[@state_mutex]
          end

          def lifecycle_phase
            :diagnostics
          end
        end

        # Production safety interface contract
        module ProductionSafetyContract
          extend ModuleContract

          def required_mutexes
            %i[@state_mutex]
          end

          def lifecycle_phase
            :production_safety
          end
        end

        # Enhanced contract validation utilities with reporting and flexible validation modes
        module ContractValidator
          # Generate a structured report of all modules, their contracts, and current state
          #
          # @param instance [Object] the Core instance to analyze
          # @return [ValidationReport] comprehensive validation report object
          def self.report(instance)
            report_data = {
              validation_timestamp: Time.now,
              core_class: instance.class.name,
              shared_state: analyze_shared_state(instance),
              shared_mutexes: analyze_shared_mutexes(instance),
              modules: analyze_modules(instance),
              cross_dependencies: analyze_cross_dependencies(instance),
              overall_status: 'unknown'
            }

            # Determine overall validation status
            all_modules_valid = report_data[:modules].values.all? { |m| m[:contract_valid] }
            all_deps_satisfied = report_data[:cross_dependencies].values.all? { |d| d[:satisfied] }

            report_data[:overall_status] = if all_modules_valid && all_deps_satisfied
                                             'valid'
                                           elsif report_data[:modules].any? { |_, m| m[:errors].any? }
                                             'invalid'
                                           else
                                             'warnings'
                                           end

            ValidationReport.new(report_data)
          end

          # Get all included modules for a specific lifecycle phase
          #
          # @param instance [Object] the Core instance to analyze
          # @param phase [Symbol] the lifecycle phase to filter by
          # @return [Array<String>] list of module names in the specified phase
          def self.modules_by_phase(instance, phase)
            modules = []

            instance.class.included_modules.each do |mod|
              next unless mod.name&.include?('Bootloader')

              module_name = mod.name.split('::').last
              contract_name = MODULE_CONTRACTS[module_name]

              next unless contract_name && const_defined?(contract_name)

              contract = const_get(contract_name)
              modules << module_name if contract.respond_to?(:lifecycle_phase) && contract.lifecycle_phase == phase
            end

            modules
          end

          # Wrapper class for validation reports with convenient output methods
          class ValidationReport
            # Initialize with report data
            # @param data [Hash] the validation report data
            def initialize(data)
              @data = data.freeze
            end

            # Return the raw report data as a hash
            # @return [Hash] the validation report data
            def to_h
              @data
            end

            # Convert the report to JSON format
            # @param pretty [Boolean] whether to format JSON prettily
            # @return [String] JSON representation of the report
            def to_json(pretty: true)
              require 'json'
              if pretty
                JSON.pretty_generate(@data)
              else
                JSON.generate(@data)
              end
            end

            # Generate a human-readable summary of the validation report
            # @return [String] formatted summary text
            def summary
              lines = []
              lines << '=== Contract Validation Summary ==='
              lines << "Generated: #{@data[:validation_timestamp]}"
              lines << "Core Class: #{@data[:core_class]}"
              lines << "Overall Status: #{@data[:overall_status].upcase}"
              lines << ''

              # Shared state summary
              state_count = @data[:shared_state].count { |_, info| info[:defined] }
              total_state = @data[:shared_state].size
              lines << "Shared State: #{state_count}/#{total_state} variables initialized"

              # Mutex summary
              mutex_count = @data[:shared_mutexes].count { |_, info| info[:valid] }
              total_mutexes = @data[:shared_mutexes].size
              lines << "Shared Mutexes: #{mutex_count}/#{total_mutexes} valid"

              # Module summary
              valid_modules = @data[:modules].count { |_, info| info[:contract_valid] }
              total_modules = @data[:modules].size
              lines << "Module Contracts: #{valid_modules}/#{total_modules} valid"

              # Dependency summary
              satisfied_deps = @data[:cross_dependencies].count { |_, info| info[:satisfied] }
              total_deps = @data[:cross_dependencies].size
              lines << "Cross Dependencies: #{satisfied_deps}/#{total_deps} satisfied"

              # Error details if any
              error_count = @data[:modules].sum { |_, info| info[:errors].size }
              if error_count.positive?
                lines << ''
                lines << '--- Validation Errors ---'
                @data[:modules].each do |name, info|
                  lines << "#{name}: #{info[:errors].join(', ')}" if info[:errors].any?
                end
              end

              lines.join("\n")
            end
          end

          # Validate all included modules meet their contracts with flexible error handling
          #
          # @param instance [Object] the Core instance to validate
          # @param strict [Boolean] if false, logs warnings instead of raising on validation failures
          # @return [Array<String>] list of validation errors (empty if valid)
          # @raise [RuntimeError] if validation fails and strict mode is enabled
          def self.validate_module_contracts!(instance, strict: true)
            errors = []

            # Validate shared state initialization
            SHARED_STATE_KEYS.each do |var|
              errors << "Missing required state variable: #{var}" unless instance.instance_variable_defined?(var)
            end

            # Validate shared mutexes
            SHARED_MUTEX_NAMES.each do |mutex|
              unless instance.instance_variable_defined?(mutex) && instance.instance_variable_get(mutex).is_a?(Mutex)
                errors << "Missing or invalid mutex: #{mutex}"
              end
            end

            # Validate module method naming patterns
            instance.class.included_modules.each do |mod|
              next unless mod.name&.include?('Bootloader')

              mod.instance_methods(false).each do |method|
                method_str = method.to_s
                next if method_str.start_with?('_') # Skip private methods

                # Check method follows naming conventions
                next if METHOD_PATTERNS.values.any? { |pattern| method_str.match?(pattern) } ||
                        %w[booted? cached_config cache_config clear_config_cache].include?(method_str)

                # Allow some common exception patterns
                unless method_str.match?(/^(subsystem|diagnostics|manifest|boot_status|reload!)$/)
                  errors << "Method #{mod.name}##{method} doesn't follow naming conventions"
                end
              end
            end

            # Handle validation results based on strict mode
            if errors.any?
              if strict
                log_validation_failure(errors)
                raise "Module contract validation failed:\n#{errors.join("\n")}"
              else
                log_validation_warnings(errors)
              end
            else
              log_validation_success(instance)
            end

            errors
          end

          # Validate module cross-dependencies using declarative CROSS_DEPENDENCIES constant
          #
          # @param instance [Object] the Core instance to validate
          # @param strict [Boolean] if false, logs warnings instead of raising on dependency failures
          # @return [Boolean] true if all dependencies are satisfied
          # @raise [RuntimeError] if dependencies are not satisfied and strict mode is enabled
          def self.validate_cross_dependencies!(instance, strict: true)
            errors = []

            # Validate dependencies from CROSS_DEPENDENCIES constant
            CROSS_DEPENDENCIES.each do |module_name, dependencies|
              # Check if module is actually included
              unless has_module?(instance, module_name)
                next # Skip validation for modules not included
              end

              # Validate required state variables
              dependencies[:state_variables]&.each do |var|
                unless instance.instance_variable_defined?(var)
                  errors << "#{module_name} requires state variable #{var} but it's not initialized"
                end
              end

              # Validate required methods
              dependencies[:methods]&.each do |method|
                unless instance.respond_to?(method)
                  errors << "#{module_name} requires method #{method} but it's not available"
                end
              end
            end

            # Handle dependency validation results
            if errors.any?
              if strict
                log_dependency_failure(errors)
                raise "Cross-dependency validation failed:\n#{errors.join("\n")}"
              else
                log_dependency_warnings(errors)
                false
              end
            else
              log_dependency_success(instance)
              true
            end
          end

          # Analyze shared state variables for the report
          # @param instance [Object] the Core instance
          # @return [Hash] analysis of shared state variables
          def self.analyze_shared_state(instance)
            SHARED_STATE_KEYS.map do |var|
              [var, {
                defined: instance.instance_variable_defined?(var),
                type: instance.instance_variable_defined?(var) ? instance.instance_variable_get(var).class.name : nil
              }]
            end.to_h
          end

          # Analyze shared mutexes for the report
          # @param instance [Object] the Core instance
          # @return [Hash] analysis of shared mutexes
          def self.analyze_shared_mutexes(instance)
            SHARED_MUTEX_NAMES.map do |mutex|
              value = instance.instance_variable_defined?(mutex) ? instance.instance_variable_get(mutex) : nil
              [mutex, {
                defined: instance.instance_variable_defined?(mutex),
                type: value&.class&.name,
                valid: value.is_a?(Mutex)
              }]
            end.to_h
          end

          # Analyze all included modules and their contracts
          # @param instance [Object] the Core instance
          # @return [Hash] analysis of included modules
          def self.analyze_modules(instance)
            modules = {}

            instance.class.included_modules.each do |mod|
              next unless mod.name&.include?('Bootloader')

              module_name = mod.name.split('::').last
              contract_name = MODULE_CONTRACTS[module_name]

              if contract_name
                contract = const_get(contract_name) if const_defined?(contract_name)
                modules[module_name] = analyze_module_contract(mod, contract, instance)
              end
            end

            modules
          end

          # Analyze a specific module contract
          # @param mod [Module] the module to analyze
          # @param contract [Module] the contract module
          # @param instance [Object] the Core instance
          # @return [Hash] module analysis
          def self.analyze_module_contract(mod, contract, instance)
            analysis = {
              lifecycle_phase: contract&.lifecycle_phase || :unknown,
              required_state_variables: contract&.required_state_variables || [],
              required_mutexes: contract&.required_mutexes || [],
              exposed_methods: contract&.exposed_methods || [],
              actual_methods: mod.instance_methods(false),
              errors: [],
              contract_valid: true
            }

            # Validate required state variables
            analysis[:required_state_variables].each do |var|
              unless instance.instance_variable_defined?(var)
                analysis[:errors] << "Missing required state variable: #{var}"
                analysis[:contract_valid] = false
              end
            end

            # Validate required mutexes
            analysis[:required_mutexes].each do |mutex|
              unless instance.instance_variable_defined?(mutex) && instance.instance_variable_get(mutex).is_a?(Mutex)
                analysis[:errors] << "Missing or invalid mutex: #{mutex}"
                analysis[:contract_valid] = false
              end
            end

            analysis
          end

          # Analyze cross-dependencies for the report
          # @param instance [Object] the Core instance
          # @return [Hash] cross-dependency analysis
          def self.analyze_cross_dependencies(instance)
            CROSS_DEPENDENCIES.map do |module_name, deps|
              [module_name, {
                module_included: has_module?(instance, module_name),
                state_variables: deps[:state_variables]&.map do |var|
                  { name: var, satisfied: instance.instance_variable_defined?(var) }
                end || [],
                methods: deps[:methods]&.map do |method|
                  { name: method, satisfied: instance.respond_to?(method) }
                end || [],
                satisfied: deps[:state_variables]&.all? { |var| instance.instance_variable_defined?(var) } &&
                  deps[:methods]&.all? { |method| instance.respond_to?(method) }
              }]
            end.to_h
          end

          # Check if instance has a specific module included
          # @param instance [Object] the Core instance
          # @param module_name [String] name of the module to check
          # @return [Boolean] true if module is included
          def self.has_module?(instance, module_name)
            instance.class.included_modules.any? { |mod| mod.name&.include?(module_name) }
          end

          # Log validation success with lightweight logging
          # @param instance [Object] the validated instance
          def self.log_validation_success(instance)
            safe_log("Contract validation passed for #{instance.class.name}", :info)
          end

          # Log validation warnings in non-strict mode
          # @param errors [Array<String>] validation errors
          def self.log_validation_warnings(errors)
            safe_log("Contract validation warnings: #{errors.join('; ')}", :warn)
          end

          # Log validation failure in strict mode
          # @param errors [Array<String>] validation errors
          def self.log_validation_failure(errors)
            safe_log("Contract validation failed: #{errors.join('; ')}", :error)
          end

          # Log dependency validation success
          # @param instance [Object] the validated instance
          def self.log_dependency_success(instance)
            safe_log("Cross-dependency validation passed for #{instance.class.name}", :info)
          end

          # Log dependency warnings in non-strict mode
          # @param errors [Array<String>] dependency errors
          def self.log_dependency_warnings(errors)
            safe_log("Cross-dependency validation warnings: #{errors.join('; ')}", :warn)
          end

          # Log dependency failure in strict mode
          # @param errors [Array<String>] dependency errors
          def self.log_dependency_failure(errors)
            safe_log("Cross-dependency validation failed: #{errors.join('; ')}", :error)
          end

          # Safe logging with fallback to stderr
          # @param message [String] message to log
          # @param level [Symbol] log level (:info, :warn, :error)
          def self.safe_log(message, level)
            if defined?(Whiskey::Core::Log)
              Whiskey::Core::Log.send(level, "[Whiskey::Contract] #{message}")
            else
              prefix = case level
                       when :info then '[INFO]'
                       when :warn then '[WARN]'
                       when :error then '[ERROR]'
                       else '[LOG]'
                       end
              warn "#{prefix} [Whiskey::Contract] #{message}"
            end
          rescue StandardError => e
            warn "[CRITICAL] Contract logging failed: #{e.message}"
            warn "[CONTRACT] #{message}"
          end
        end

        # Thread-safe custom contract registration system for extending the bootloader
        # Allows runtime registration of additional contracts without modifying core constants
        module CustomContracts
          @custom_contracts = {}
          @contracts_mutex = Mutex.new

          class << self
            # Register a custom contract for dynamic modules
            #
            # @param name [String, Symbol] the module name to register
            # @param contract_module [Module] the contract module defining the interface
            # @return [void]
            # @raise [ArgumentError] if name or contract_module is invalid
            def register(name, contract_module)
              name_str = name.to_s

              # Validate input parameters
              raise ArgumentError, 'Contract name cannot be empty' if name_str.empty?
              raise ArgumentError, 'Contract module must be a Module' unless contract_module.is_a?(Module)

              @contracts_mutex.synchronize do
                # Check if contract already exists
                if @custom_contracts.key?(name_str)
                  # Allow re-registration with warning
                  safe_log("Re-registering custom contract for '#{name_str}'", :warn)
                end

                @custom_contracts[name_str] = contract_module
                safe_log("Registered custom contract '#{name_str}' -> #{contract_module}", :info)
              end
            end

            # Get all currently registered custom contracts
            #
            # @return [Hash<String, Module>] mapping of contract names to modules
            def contracts
              @contracts_mutex.synchronize do
                @custom_contracts.dup
              end
            end

            # Check if a custom contract is registered
            #
            # @param name [String, Symbol] the contract name to check
            # @return [Boolean] true if the contract is registered
            def registered?(name)
              @contracts_mutex.synchronize do
                @custom_contracts.key?(name.to_s)
              end
            end

            # Unregister a custom contract
            #
            # @param name [String, Symbol] the contract name to unregister
            # @return [Module, nil] the unregistered contract module, or nil if not found
            def unregister(name)
              @contracts_mutex.synchronize do
                removed = @custom_contracts.delete(name.to_s)
                safe_log("Unregistered custom contract '#{name}'", :info) if removed
                removed
              end
            end

            # Clear all custom contracts (primarily for testing)
            #
            # @return [void]
            def clear!
              @contracts_mutex.synchronize do
                count = @custom_contracts.size
                @custom_contracts.clear
                safe_log("Cleared #{count} custom contracts", :info) if count.positive?
              end
            end

            # Get the effective MODULE_CONTRACTS including custom registrations
            # Merges the core MODULE_CONTRACTS with custom registrations
            #
            # @return [Hash<String, Symbol>] combined contract mapping
            def effective_contracts
              @contracts_mutex.synchronize do
                # Convert custom contract modules to symbols for consistency
                custom_symbol_contracts = @custom_contracts.transform_values do |contract_module|
                  contract_module.name&.split('::')&.last&.to_sym || :CustomContract
                end

                MODULE_CONTRACTS.merge(custom_symbol_contracts)
              end
            end

            private

            # Thread-safe logging for custom contract operations
            # @param message [String] message to log
            # @param level [Symbol] log level (:info, :warn, :error)
            def safe_log(message, level)
              if defined?(Whiskey::Core::Log)
                Whiskey::Core::Log.send(level, "[Whiskey::CustomContract] #{message}")
              else
                prefix = case level
                         when :info then '[INFO]'
                         when :warn then '[WARN]'
                         when :error then '[ERROR]'
                         else '[LOG]'
                         end
                warn "#{prefix} [Whiskey::CustomContract] #{message}"
              end
            rescue StandardError => e
              warn "[CRITICAL] Custom contract logging failed: #{e.message}"
              warn "[CUSTOM_CONTRACT] #{message}"
            end
          end
        end
      end
    end
  end
end
