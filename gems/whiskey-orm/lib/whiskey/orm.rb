# frozen_string_literal: true

require 'whiskey/orm/version'
require 'whiskey/orm/core'
require 'logger'
require 'set'

module Whiskey
  module ORM
    # Enhanced module registry containing all available ingredients with extended metadata
    MODULE_REGISTRY = {
      validations: {
        file: 'whiskey/orm/validations',
        dependencies: [],
        injection: :include,
        targets: %i[glass model],
        description: 'Presence, uniqueness, length, and format validations',
        version: '1.0.0',
        optional: false,
        author: 'Whiskey::ORM Team',
        injector: nil
      },
      associations: {
        file: 'whiskey/orm/associations',
        dependencies: [:query],
        injection: :include,
        targets: %i[glass model],
        description: 'has_one, has_many, belongs_to relationship management',
        version: '1.0.0',
        optional: true,
        author: 'Whiskey::ORM Team',
        injector: nil
      },
      query: {
        file: 'whiskey/orm/query',
        dependencies: [],
        injection: :extend,
        targets: %i[glass model],
        description: 'Chainable query DSL for filtering and ordering',
        version: '1.0.0',
        optional: true,
        author: 'Whiskey::ORM Team',
        injector: proc { |target_class, ingredient_module|
          # Custom injection hook example for query module
          target_class.define_singleton_method(:query_builder_class) { ingredient_module::QueryBuilder }
        }
      },
      serialization: {
        file: 'whiskey/orm/serialization',
        dependencies: [],
        injection: :include,
        targets: %i[glass model],
        description: 'JSON, XML, and YAML conversion capabilities',
        version: '1.0.0',
        optional: true,
        author: 'Whiskey::ORM Team',
        injector: nil
      },
      callbacks: {
        file: 'whiskey/orm/callbacks',
        dependencies: [],
        injection: :prepend,
        targets: %i[glass model],
        description: 'Lifecycle hooks for fill, drink, and empty operations',
        version: '1.0.0',
        optional: true,
        author: 'Whiskey::ORM Team',
        injector: nil
      },
      persistence: {
        file: 'whiskey/orm/persistence',
        dependencies: [:callbacks],
        injection: :include,
        targets: %i[glass model],
        description: 'Database adapter system for drinking Glass objects',
        version: '1.0.0',
        optional: true,
        author: 'Whiskey::ORM Team',
        injector: nil
      }
    }.freeze

    # Global adapter registry for persistence backends
    ADAPTERS = {}.freeze

    # Whiskey::ORM error hierarchy
    class Error < StandardError; end
    class IngredientError < Error; end
    class AdapterError < Error; end
    class DependencyError < Error; end
    class CircularDependencyError < DependencyError; end

    # Enhanced logging system using Ruby's Logger
    class DistilleryLogger
      attr_reader :logger, :level

      def initialize(output = $stdout, level = Logger::INFO)
        @logger = Logger.new(output)
        @logger.progname = 'Whiskey::ORM'
        @logger.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} -- #{progname}: #{msg}\n"
        end
        @level = level
        @logger.level = level
      end

      def debug(message)
        @logger.debug(message)
      end

      def info(message)
        @logger.info(message)
      end

      def warn(message)
        @logger.warn(message)
      end

      def error(message)
        @logger.error(message)
      end

      def fatal(message)
        @logger.fatal(message)
      end

      def level=(new_level)
        @level = new_level
        @logger.level = new_level
      end
    end

    # Legacy Log module for backward compatibility
    module Log
      class << self
        def logger
          @logger ||= DistilleryLogger.new
        end

        def info(message)
          logger.info(message)
        end

        def warn(message)
          logger.warn(message)
        end

        def error(message)
          logger.error(message)
        end

        def debug(message)
          logger.debug(message)
        end

        def fatal(message)
          logger.fatal(message)
        end
      end
    end

    # The Decanter manages ORM configuration and ingredient mixing with enhanced features
    class Decanter
      attr_accessor :raise_on_error
      attr_reader :enabled_ingredients, :persistence_config, :current_adapter_instance

      def initialize
        @enabled_ingredients = Set.new
        @persistence_config = { adapter: :memory, config: {} }
        @module_metadata = {}
        @current_adapter_instance = nil
        @raise_on_error = true
        @mutex = Mutex.new

        # Auto-load from config if available
        load_from_config if config_available?
      end

      # Load ORM configuration from Whiskey::Config
      # Integrates with the unified configuration system
      # @return [Boolean] true if configuration was loaded successfully
      def load_from_config
        return false unless config_available?

        begin
          # Load the unified config if not already loaded
          Whiskey::Config.load! unless Whiskey::Config.loaded?

          orm_config = Whiskey::Config.section(:ORM)
          return false if orm_config.empty?

          Log.info('Loading ORM configuration from Whiskey::Config')

          # Configure error handling if specified
          if orm_config.key?('RaiseOnError')
            self.raise_on_error = orm_config['RaiseOnError']
            Log.debug("Set raise_on_error to #{@raise_on_error}")
          end

          # Auto-enable ingredients based on configuration flags
          load_ingredients_from_config(orm_config)

          # Configure persistence adapter if specified
          load_persistence_from_config(orm_config)

          Log.info('Successfully loaded ORM configuration from unified config')
          true
        rescue StandardError => e
          Log.error("Failed to load ORM configuration: #{e.message}")
          false
        end
      end

      # Reload configuration from Whiskey::Config
      # @return [Boolean] true if successfully reloaded
      def reload_from_config
        return false unless config_available?

        begin
          # Reload the configuration file
          Whiskey::Config.reload!

          # Clear current state (keeping enabled ingredients for safety)
          Log.info('Reloading ORM configuration from updated config file')

          # Re-apply configuration
          load_from_config
        rescue StandardError => e
          Log.error("Failed to reload ORM configuration: #{e.message}")
          false
        end
      end

      # Configure error handling behavior
      # @param raise_errors [Boolean] whether to raise errors or just log them

      # Enable an ingredient (module) with automatic dependency resolution and circular dependency detection
      # @param ingredient_name [Symbol] the name of the ingredient to enable
      # @param options [Hash] optional configuration for the ingredient
      # @return [Boolean] true if successfully enabled
      def enable(ingredient_name, options = {})
        @mutex.synchronize do
          ingredient_name = ingredient_name.to_sym

          unless MODULE_REGISTRY.key?(ingredient_name)
            handle_error(IngredientError,
                         "Unknown ingredient: #{ingredient_name}. Available: #{available_ingredients.join(', ')}")
            return false
          end

          # Check for circular dependencies before enabling
          begin
            detect_circular_dependencies(ingredient_name)
          rescue CircularDependencyError => e
            handle_error(e.class, e.message)
            return false
          end

          # Auto-enable dependencies first
          MODULE_REGISTRY[ingredient_name][:dependencies].each do |dependency|
            next if enabled?(dependency)

            Log.info("Auto-enabling dependency: #{dependency} (required by #{ingredient_name})")
            unless enable(dependency)
              handle_error(DependencyError, "Failed to enable dependency #{dependency} for #{ingredient_name}")
              return false
            end
          end

          # Pour the ingredient module
          success = pour_ingredient(ingredient_name)

          if success
            @enabled_ingredients << ingredient_name
            track_ingredient_metadata(ingredient_name, options)
            Log.info("Enabled ingredient: #{ingredient_name}")
          else
            handle_error(IngredientError, "Failed to enable ingredient: #{ingredient_name}")
          end

          success
        end
      end

      # Disable an ingredient (if it supports unloading)
      # @param ingredient_name [Symbol] the name of the ingredient to disable
      # @return [Boolean] true if successfully disabled
      def disable(ingredient_name)
        @mutex.synchronize do
          ingredient_name = ingredient_name.to_sym

          unless enabled?(ingredient_name)
            Log.warn("Ingredient #{ingredient_name} is not enabled")
            return false
          end

          # Check if any enabled ingredients depend on this one
          dependents = @enabled_ingredients.select do |enabled|
            MODULE_REGISTRY[enabled][:dependencies].include?(ingredient_name)
          end

          unless dependents.empty?
            handle_error(DependencyError, "Cannot disable #{ingredient_name}: required by #{dependents.join(', ')}")
            return false
          end

          # Attempt to unload if the module supports it
          ingredient_module = get_ingredient_module(ingredient_name)
          if ingredient_module.respond_to?(:unload!)
            begin
              ingredient_module.unload!
              Log.info("Unloaded ingredient: #{ingredient_name}")
            rescue StandardError => e
              Log.warn("Ingredient #{ingredient_name} unload failed: #{e.message}")
            end
          else
            Log.warn("Ingredient #{ingredient_name} does not support dynamic unloading")
          end

          @enabled_ingredients.delete(ingredient_name)
          @module_metadata.delete(ingredient_name)
          Log.info("Disabled ingredient: #{ingredient_name}")
          true
        end
      end

      # Reload an ingredient by safely disabling and re-enabling it
      # @param ingredient_name [Symbol] the name of the ingredient to reload
      # @return [Boolean] true if successfully reloaded
      def reload(ingredient_name)
        @mutex.synchronize do
          ingredient_name = ingredient_name.to_sym

          unless enabled?(ingredient_name)
            Log.warn("Cannot reload #{ingredient_name}: not currently enabled")
            return false
          end

          Log.info("Reloading ingredient: #{ingredient_name}")

          # Store current options for re-enabling
          current_options = @module_metadata[ingredient_name]&.[](:options) || {}

          # Disable the ingredient
          unless disable(ingredient_name)
            handle_error(IngredientError, "Failed to disable #{ingredient_name} during reload")
            return false
          end

          # Clear the require cache for the ingredient file if possible
          registry_data = MODULE_REGISTRY[ingredient_name]
          file_path = registry_data[:file]

          # Remove from $LOADED_FEATURES to force reload
          $LOADED_FEATURES.delete_if { |loaded_file| loaded_file.include?(file_path) }

          # Re-enable the ingredient
          if enable(ingredient_name, current_options)
            Log.info("Successfully reloaded ingredient: #{ingredient_name}")
            true
          else
            handle_error(IngredientError, "Failed to re-enable #{ingredient_name} during reload")
            false
          end
        end
      end

      # Configure persistence adapter with lifecycle hooks
      # @param adapter_name [Symbol] the adapter name
      # @param config [Hash] the adapter configuration
      def persistence(adapter_name, config = {})
        @mutex.synchronize do
          adapter_name = adapter_name.to_sym

          # Call teardown on current adapter if it exists
          if @current_adapter_instance.respond_to?(:teardown)
            begin
              @current_adapter_instance.teardown
              Log.debug('Called teardown on previous adapter')
            rescue StandardError => e
              Log.warn("Error during adapter teardown: #{e.message}")
            end
          end

          # Validate and setup new adapter if registered
          if ADAPTERS.key?(adapter_name)
            adapter_class = ADAPTERS[adapter_name]
            begin
              # Test adapter instantiation
              test_adapter = adapter_class.new(config)

              # Call setup if available
              if test_adapter.respond_to?(:setup)
                test_adapter.setup(config)
                Log.debug("Called setup on new adapter: #{adapter_name}")
              end

              @current_adapter_instance = test_adapter
              Log.debug("Validated persistence adapter: #{adapter_name}")
            rescue StandardError => e
              handle_error(AdapterError, "Invalid adapter configuration for #{adapter_name}: #{e.message}")
              return false
            end
          else
            Log.warn("Persistence adapter #{adapter_name} not yet registered")
          end

          @persistence_config = { adapter: adapter_name, config: config }
          Log.info("Configured persistence adapter: #{adapter_name}")
          true
        end
      end

      # Check if an ingredient is enabled
      # @param ingredient_name [Symbol] the ingredient name
      # @return [Boolean] true if enabled
      def enabled?(ingredient_name)
        @enabled_ingredients.include?(ingredient_name.to_sym)
      end

      # Get list of available ingredients
      # @return [Array<Symbol>] available ingredient names
      def available_ingredients
        MODULE_REGISTRY.keys
      end

      # Get detailed information about ingredients with extended metadata
      # @param ingredient_name [Symbol, nil] specific ingredient or all if nil
      # @return [Hash] ingredient information
      def ingredient_info(ingredient_name = nil)
        if ingredient_name
          ingredient_name = ingredient_name.to_sym
          return {} unless MODULE_REGISTRY.key?(ingredient_name)

          info = MODULE_REGISTRY[ingredient_name].dup
          info[:enabled] = enabled?(ingredient_name)
          info[:metadata] = @module_metadata[ingredient_name] || {}
          info
        else
          MODULE_REGISTRY.map do |name, data|
            info = data.dup
            info[:name] = name
            info[:enabled] = enabled?(name)
            info[:metadata] = @module_metadata[name] || {}
            info
          end
        end
      end

      # Enable all ingredients (respecting dependencies)
      def enable_all
        # Enable required ingredients first, then optional ones
        required_ingredients = MODULE_REGISTRY.reject { |_, data| data[:optional] }.keys
        optional_ingredients = MODULE_REGISTRY.select { |_, data| data[:optional] }.keys

        (required_ingredients + optional_ingredients).each { |ingredient| enable(ingredient) }
      end

      # Get currently enabled ingredients
      # @return [Array<Symbol>] enabled ingredient names
      def enabled_ingredients_list
        @enabled_ingredients.to_a
      end

      private

      # Check if Whiskey::Config is available and has been loaded
      # @return [Boolean] true if config system is available
      def config_available?
        require 'whiskey/core/config' unless defined?(Whiskey::Config)
        defined?(Whiskey::Config) && Whiskey::Config.respond_to?(:section)
      rescue LoadError
        false
      end

      # Load ingredients from configuration
      # @param orm_config [Hash] the ORM configuration section
      def load_ingredients_from_config(orm_config)
        # Handle individual ingredient flags (e.g., ORM.Ingredients.Validations)
        if orm_config.key?('Ingredients')
          ingredients_config = orm_config['Ingredients']

          MODULE_REGISTRY.each_key do |ingredient_name|
            ingredient_key = ingredient_name.to_s.capitalize

            # Check if ingredient is explicitly enabled/disabled
            next unless ingredients_config.key?(ingredient_key)

            should_enable = ingredients_config[ingredient_key]

            if should_enable && !enabled?(ingredient_name)
              Log.info("Auto-enabling ingredient from config: #{ingredient_name}")
              enable(ingredient_name)
            elsif !should_enable && enabled?(ingredient_name)
              Log.info("Auto-disabling ingredient from config: #{ingredient_name}")
              disable(ingredient_name)
            end
          end
        end

        # Handle global enable flags (e.g., ORM.EnableAll)
        if orm_config.key?('EnableAll') && orm_config['EnableAll']
          Log.info('Enabling all ingredients from config')
          enable_all
        end

        # Handle specific ingredient lists (e.g., ORM.EnabledIngredients)
        return unless orm_config.key?('EnabledIngredients')

        enabled_list = orm_config['EnabledIngredients']
        return unless enabled_list.is_a?(Array)

        enabled_list.each do |ingredient_name|
          ingredient_symbol = ingredient_name.to_sym
          if MODULE_REGISTRY.key?(ingredient_symbol) && !enabled?(ingredient_symbol)
            Log.info("Auto-enabling ingredient from list: #{ingredient_symbol}")
            enable(ingredient_symbol)
          end
        end
      end

      # Load persistence configuration
      # @param orm_config [Hash] the ORM configuration section
      def load_persistence_from_config(orm_config)
        # Handle persistence adapter configuration (e.g., ORM.Persistence.Adapter)
        if orm_config.key?('Persistence')
          persistence_config = orm_config['Persistence']

          if persistence_config.key?('Adapter')
            adapter_name = persistence_config['Adapter'].to_sym
            adapter_config = persistence_config['Config'] || {}

            Log.info("Configuring persistence adapter from config: #{adapter_name}")
            persistence(adapter_name, adapter_config)
          end
        end

        # Handle direct adapter configuration (e.g., ORM.Adapter)
        return unless orm_config.key?('Adapter')

        adapter_name = orm_config['Adapter'].to_sym
        adapter_config = orm_config['AdapterConfig'] || {}

        Log.info("Configuring adapter from config: #{adapter_name}")
        persistence(adapter_name, adapter_config)
      end

      # Detect circular dependencies in ingredient dependencies
      # @param ingredient_name [Symbol] the ingredient to check
      # @param visited [Set] already visited ingredients in current path
      # @param path [Array] current dependency path for error reporting
      # @raise [CircularDependencyError] if circular dependency detected
      def detect_circular_dependencies(ingredient_name, visited = Set.new, path = [])
        if visited.include?(ingredient_name)
          cycle_path = path[path.index(ingredient_name)..] + [ingredient_name]
          raise CircularDependencyError, "Circular dependency detected: #{cycle_path.join(' -> ')}"
        end

        visited.add(ingredient_name)
        current_path = path + [ingredient_name]

        MODULE_REGISTRY[ingredient_name][:dependencies].each do |dependency|
          detect_circular_dependencies(dependency, visited.dup, current_path)
        end
      end

      # Handle errors based on configuration (raise or log)
      # @param error_class [Class] the error class to raise/log
      # @param message [String] the error message
      def handle_error(error_class, message)
        raise error_class, message if @raise_on_error


        Log.error("#{error_class.name}: #{message}")
      end

      # Pour (load and inject) an ingredient module
      # @param ingredient_name [Symbol] the ingredient to pour
      # @return [Boolean] true if successful
      def pour_ingredient(ingredient_name)
        registry_data = MODULE_REGISTRY[ingredient_name]

        begin
          # Load the module file
          require registry_data[:file]

          # Get the loaded module
          ingredient_module = get_ingredient_module(ingredient_name)
          unless ingredient_module
            Log.error("Could not find ingredient module after loading: #{ingredient_name}")
            return false
          end

          # Mix the ingredient into target classes
          mix_into_targets(ingredient_module, registry_data)
          true
        rescue LoadError => e
          Log.error("Failed to load ingredient #{ingredient_name}: #{e.message}")
          false
        rescue StandardError => e
          Log.error("Error pouring ingredient #{ingredient_name}: #{e.message}")
          false
        end
      end

      # Get the ingredient module constant
      # @param ingredient_name [Symbol] the ingredient name
      # @return [Module, nil] the ingredient module or nil
      def get_ingredient_module(ingredient_name)
        module_name = ingredient_name.to_s.split('_').map(&:capitalize).join
        Whiskey::ORM::Ingredients.const_get(module_name)
      rescue NameError
        nil
      end

      # Mix ingredient into target Glass classes
      # @param ingredient_module [Module] the ingredient to mix
      # @param registry_data [Hash] the ingredient's registry data
      def mix_into_targets(ingredient_module, registry_data)
        injection_method = registry_data[:injection]
        targets = registry_data[:targets]
        custom_injector = registry_data[:injector]

        # Mix into Glass class if targeted
        if targets.include?(:glass)
          target_class = Whiskey::ORM::Core::Glass
          mix_into_glass(target_class, ingredient_module, injection_method)

          # Execute custom injection hook if provided
          if custom_injector.is_a?(Proc)
            begin
              custom_injector.call(target_class, ingredient_module)
              Log.debug("Executed custom injector for #{ingredient_module} into #{target_class}")
            rescue StandardError => e
              Log.warn("Custom injector failed for #{ingredient_module}: #{e.message}")
            end
          end
        end

        # Mix into Model class if it exists and is targeted
        return unless targets.include?(:model) && defined?(Whiskey::ORM::Core::Model)

        target_class = Whiskey::ORM::Core::Model
        mix_into_glass(target_class, ingredient_module, injection_method)

        # Execute custom injection hook if provided
        return unless custom_injector.is_a?(Proc)

        begin
          custom_injector.call(target_class, ingredient_module)
          Log.debug("Executed custom injector for #{ingredient_module} into #{target_class}")
        rescue StandardError => e
          Log.warn("Custom injector failed for #{ingredient_module}: #{e.message}")
        end
      end

      # Mix an ingredient module into a specific Glass class
      # @param glass_class [Class] the target class
      # @param ingredient_module [Module] the ingredient to mix
      # @param injection_method [Symbol] how to inject (:include, :extend, :prepend)
      def mix_into_glass(glass_class, ingredient_module, injection_method)
        case injection_method
        when :include
          glass_class.include(ingredient_module)
        when :extend
          glass_class.extend(ingredient_module)
        when :prepend
          glass_class.prepend(ingredient_module)
        else
          Log.error("Unknown injection method: #{injection_method}")
          return false
        end

        Log.debug("Mixed #{ingredient_module} into #{glass_class} via #{injection_method}")
        true
      rescue StandardError => e
        Log.error("Failed to mix ingredient into #{glass_class}: #{e.message}")
        false
      end

      # Track metadata about loaded ingredients with enhanced information
      # @param ingredient_name [Symbol] the ingredient name
      # @param options [Hash] loading options
      def track_ingredient_metadata(ingredient_name, options)
        registry_data = MODULE_REGISTRY[ingredient_name]
        @module_metadata[ingredient_name] = {
          loaded_at: Time.now,
          options: options,
          targets_injected: registry_data[:targets],
          version: registry_data[:version],
          optional: registry_data[:optional],
          author: registry_data[:author],
          has_custom_injector: !registry_data[:injector].nil?
        }
      end
    end

    # Module namespace for all ingredient modules
    module Ingredients
    end

    class << self
      # Get the global decanter instance
      # @return [Decanter] the configuration decanter
      def decanter
        @decanter ||= Decanter.new
      end

      # Configure the ORM with a block, including error handling options
      # @yield [Decanter] the decanter instance for configuration
      # @example
      #   Whiskey::ORM.configure do |config|
      #     config.raise_on_error = false  # Log errors instead of raising
      #     config.enable :validations
      #     config.enable :persistence
      #   end
      def configure
        yield(decanter) if block_given?
      end

      # Configure logging system
      # @param output [IO] output stream for logging
      # @param level [Integer] logging level (Logger::DEBUG, INFO, WARN, ERROR, FATAL)
      def configure_logging(output: $stdout, level: Logger::INFO)
        Log.logger.logger = Logger.new(output)
        Log.logger.level = level
      end

      # Enable an ingredient
      # @param ingredient_name [Symbol] the ingredient to enable
      # @param options [Hash] optional configuration
      # @return [Boolean] true if successful
      def enable(ingredient_name, options = {})
        decanter.enable(ingredient_name, options)
      end

      # Disable an ingredient
      # @param ingredient_name [Symbol] the ingredient to disable
      # @return [Boolean] true if successful
      def disable(ingredient_name)
        decanter.disable(ingredient_name)
      end

      # Reload an ingredient
      # @param ingredient_name [Symbol] the ingredient to reload
      # @return [Boolean] true if successful
      def reload(ingredient_name)
        decanter.reload(ingredient_name)
      end

      # Configure persistence adapter
      # @param adapter_name [Symbol] the adapter name
      # @param config [Hash] adapter configuration
      def persistence(adapter_name, config = {})
        decanter.persistence(adapter_name, config)
      end

      # Get persistence configuration
      # @return [Hash] persistence configuration
      def persistence_config
        decanter.persistence_config
      end

      # Check if ingredient is enabled
      # @param ingredient_name [Symbol] the ingredient name
      # @return [Boolean] true if enabled
      def enabled?(ingredient_name)
        decanter.enabled?(ingredient_name)
      end

      # Get available ingredients
      # @return [Array<Symbol>] available ingredient names
      def available_ingredients
        decanter.available_ingredients
      end

      # Get ingredient information
      # @param ingredient_name [Symbol, nil] specific ingredient or all
      # @return [Hash, Array] ingredient information
      def ingredient_info(ingredient_name = nil)
        decanter.ingredient_info(ingredient_name)
      end
      alias module_info ingredient_info # Backward compatibility

      # Enable all ingredients
      def enable_all
        decanter.enable_all
      end

      # Get enabled ingredients
      # @return [Array<Symbol>] enabled ingredient names
      def enabled_ingredients
        decanter.enabled_ingredients_list
      end

      # Register a persistence adapter
      # @param name [Symbol] adapter name
      # @param adapter_class [Class] adapter class
      def register_adapter(name, adapter_class)
        ADAPTERS[name.to_sym] = adapter_class
        Log.info("Registered persistence adapter: #{name}")
      end

      # Get registered adapters
      # @return [Hash] registered adapters
      def adapters
        ADAPTERS.dup
      end

      # Load all enabled ingredients (for initialization)
      def pour_all_enabled
        decanter.enabled_ingredients_list.each do |ingredient|
          Log.debug("Re-pouring enabled ingredient: #{ingredient}")
        end
      end

      # Set error handling behavior globally
      # @param raise_errors [Boolean] whether to raise errors or log them
      def raise_on_error=(raise_errors)
        decanter.raise_on_error = raise_errors
      end

      # Get current error handling behavior
      # @return [Boolean] whether errors are raised or logged
      def raise_on_error?
        decanter.raise_on_error
      end
    end

    # Set up dynamic autoloading for all ingredients
    MODULE_REGISTRY.each do |ingredient_name, data|
      autoload_name = ingredient_name.to_s.split('_').map(&:capitalize).join.to_sym
      Ingredients.autoload(autoload_name, data[:file])
    end

    # Register default memory adapter at module load time
    begin
      require 'whiskey/orm/persistence'
      if defined?(Whiskey::ORM::Ingredients::Persistence)
        register_adapter(:memory, Whiskey::ORM::Ingredients::Persistence::MemoryAdapter)
      end
    rescue LoadError
      # Persistence module not available yet
    end

    # Register ORM with the global Whiskey boot system
    # Load bootloader if not already available
    begin
      require 'whiskey/core/bootloader' unless defined?(Whiskey::Bootloader)
      Whiskey.register_subsystem(:ORM, self) if defined?(Whiskey::Bootloader)
    rescue LoadError
      # Bootloader not available yet - will be registered when bootloader loads
    end

    # For future subsystems that want to define their own Decanter,
    # they can follow this pattern:
    # ::Whiskey.register_subsystem(:Web, Whiskey::Web) if defined?(::Whiskey::Web)
  end
end
