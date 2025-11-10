# frozen_string_literal: true

module Whiskey
  module ORM
    module Ingredients
      # Optional persistence ingredient for Glass objects
      # Provides pluggable database adapters and drink mechanism for persisting data
      module Persistence
        def self.included(base)
          base.extend(ClassMethods)
          base.include(InstanceMethods)
        end

        # Registry for managing database adapters
        # Provides a centralized way to register and retrieve adapters
        class AdapterRegistry
          class << self
            # Get the hash of registered adapters
            # @return [Hash] hash of adapter name to adapter class mappings
            def adapters
              @adapters ||= {}
            end

            # Register a new database adapter
            # @param name [Symbol] the name of the adapter
            # @param adapter_class [Class] the adapter class that implements BaseAdapter
            # @raise [AdapterError] if adapter_class doesn't inherit from BaseAdapter
            def register(name, adapter_class)
              unless adapter_class.ancestors.include?(BaseAdapter)
                raise AdapterError, 'Adapter must inherit from BaseAdapter'
              end

              adapters[name.to_sym] = adapter_class
            end

            # Retrieve an adapter class by name
            # @param name [Symbol] the name of the adapter
            # @return [Class] the adapter class
            # @raise [AdapterError] if adapter is not found
            def get(name)
              adapters[name.to_sym] || raise(AdapterError,
                                             "Unknown adapter: #{name}. Available: #{available_adapters.join(', ')}")
            end

            # Get list of available adapter names
            # @return [Array<Symbol>] array of registered adapter names
            def available_adapters
              adapters.keys
            end

            # Check if an adapter is registered
            # @param name [Symbol] the adapter name to check
            # @return [Boolean] true if adapter is registered
            def registered?(name)
              adapters.key?(name.to_sym)
            end

            # Remove an adapter from the registry
            # @param name [Symbol] the adapter name to remove
            def unregister(name)
              adapters.delete(name.to_sym)
            end

            # Clear all registered adapters (useful for testing)
            def clear
              @adapters = {}
            end
          end
        end

        # Base adapter class that all database adapters must inherit from
        # Defines the interface that all persistence adapters must implement
        class BaseAdapter
          attr_reader :config

          # Initialize the adapter with configuration
          # @param config [Hash] adapter-specific configuration options
          def initialize(config = {})
            @config = config.dup.freeze
            validate_config if respond_to?(:validate_config, true)
          end

          # Connect to the database
          # @raise [NotImplementedError] if not implemented by subclass
          def connect
            raise NotImplementedError, 'Subclasses must implement #connect'
          end

          # Disconnect from the database
          # @raise [NotImplementedError] if not implemented by subclass
          def disconnect
            raise NotImplementedError, 'Subclasses must implement #disconnect'
          end

          # Check if currently connected to the database
          # @return [Boolean] true if connected
          # @raise [NotImplementedError] if not implemented by subclass
          def connected?
            raise NotImplementedError, 'Subclasses must implement #connected?'
          end

          # Insert a new record into the database
          # @param table_name [String, Symbol] the table name
          # @param attributes [Hash] the record attributes
          # @return [Hash] the inserted record with any generated fields (like id)
          # @raise [NotImplementedError] if not implemented by subclass
          def insert(table_name, attributes)
            raise NotImplementedError, 'Subclasses must implement #insert'
          end

          # Update an existing record in the database
          # @param table_name [String, Symbol] the table name
          # @param id [Object] the record id
          # @param attributes [Hash] the attributes to update
          # @return [Hash, nil] the updated record or nil if not found
          # @raise [NotImplementedError] if not implemented by subclass
          def update(table_name, id, attributes)
            raise NotImplementedError, 'Subclasses must implement #update'
          end

          # Delete a record from the database
          # @param table_name [String, Symbol] the table name
          # @param id [Object] the record id
          # @return [Boolean] true if record was deleted
          # @raise [NotImplementedError] if not implemented by subclass
          def delete(table_name, id)
            raise NotImplementedError, 'Subclasses must implement #delete'
          end

          # Find a single record by id
          # @param table_name [String, Symbol] the table name
          # @param id [Object] the record id
          # @return [Hash, nil] the record attributes or nil if not found
          # @raise [NotImplementedError] if not implemented by subclass
          def find(table_name, id)
            raise NotImplementedError, 'Subclasses must implement #find'
          end

          # Find multiple records by conditions
          # @param table_name [String, Symbol] the table name
          # @param conditions [Hash] the search conditions
          # @return [Array<Hash>] array of matching records
          # @raise [NotImplementedError] if not implemented by subclass
          def find_by(table_name, conditions)
            raise NotImplementedError, 'Subclasses must implement #find_by'
          end

          # Execute a raw query
          # @param query [String] the query to execute
          # @param params [Array] query parameters
          # @return [Array] query results
          # @raise [NotImplementedError] if not implemented by subclass
          def execute(query, params = [])
            raise NotImplementedError, 'Subclasses must implement #execute'
          end

          # Count records matching conditions
          # @param table_name [String, Symbol] the table name
          # @param conditions [Hash] the search conditions
          # @return [Integer] the count of matching records
          # @raise [NotImplementedError] if not implemented by subclass
          def count(table_name, conditions = {})
            raise NotImplementedError, 'Subclasses must implement #count'
          end

          # Check if any records exist matching conditions
          # @param table_name [String, Symbol] the table name
          # @param conditions [Hash] the search conditions
          # @return [Boolean] true if any records match
          def exists?(table_name, conditions)
            count(table_name, conditions).positive?
          end

          # Begin a database transaction
          # @yield block to execute within transaction
          # @return [Object] the result of the block
          def transaction
            raise ArgumentError, 'Transaction requires a block' unless block_given?

            yield
          end
        end

        # Simple in-memory adapter for testing and development
        # Stores data in Ruby hashes and arrays for quick prototyping
        class MemoryAdapter < BaseAdapter
          # Initialize the memory adapter
          # @param config [Hash] configuration options (mostly ignored for memory adapter)
          def initialize(config = {})
            super
            @data = {}
            @connected = false
            @transaction_level = 0
            @transaction_data = nil
          end

          # Connect to the in-memory database (always succeeds)
          # @return [true] always returns true
          def connect
            @connected = true
          end

          # Disconnect from the in-memory database
          # @return [true] always returns true
          def disconnect
            @connected = false
            @data&.clear
            true
          end

          # Check if connected to the in-memory database
          # @return [Boolean] true if connected
          def connected?
            @connected
          end

          # Insert a new record into the specified table
          # @param table_name [String, Symbol] the table name
          # @param attributes [Hash] the record attributes
          # @return [Hash] the inserted record with generated id
          # @raise [PersistenceError] if insert fails
          def insert(table_name, attributes)
            ensure_connected!
            ensure_table_exists(table_name)

            begin
              id = generate_id(table_name)
              record = attributes.dup
              record[:id] = id
              record[:created_at] = Time.now unless record.key?(:created_at)
              record[:updated_at] = record[:created_at]

              get_table(table_name) << record
              record.dup
            rescue StandardError => e
              raise PersistenceError, "Failed to insert record: #{e.message}"
            end
          end

          # Update an existing record
          # @param table_name [String, Symbol] the table name
          # @param id [Object] the record id
          # @param attributes [Hash] the attributes to update
          # @return [Hash, nil] the updated record or nil if not found
          # @raise [PersistenceError] if update fails
          def update(table_name, id, attributes)
            ensure_connected!
            ensure_table_exists(table_name)

            begin
              record = find_record_by_id(table_name, id)
              return nil unless record

              record.merge!(attributes.reject { |k, _| k.to_sym == :id })
              record[:updated_at] = Time.now
              record.dup
            rescue StandardError => e
              raise PersistenceError, "Failed to update record: #{e.message}"
            end
          end

          # Delete a record by id
          # @param table_name [String, Symbol] the table name
          # @param id [Object] the record id
          # @return [Boolean] true if record was found and deleted
          # @raise [PersistenceError] if delete fails
          def delete(table_name, id)
            ensure_connected!
            ensure_table_exists(table_name)

            begin
              table = get_table(table_name)
              initial_size = table.size
              table.reject! { |record| record[:id] == id }
              table.size < initial_size
            rescue StandardError => e
              raise PersistenceError, "Failed to delete record: #{e.message}"
            end
          end

          # Find a single record by id
          # @param table_name [String, Symbol] the table name
          # @param id [Object] the record id
          # @return [Hash, nil] the record or nil if not found
          def find(table_name, id)
            ensure_connected!
            ensure_table_exists(table_name)
            find_record_by_id(table_name, id)&.dup
          end

          # Find multiple records by conditions
          # @param table_name [String, Symbol] the table name
          # @param conditions [Hash] the search conditions
          # @return [Array<Hash>] array of matching records
          def find_by(table_name, conditions)
            ensure_connected!
            ensure_table_exists(table_name)

            get_table(table_name).select do |record|
              conditions.all? { |key, value| matches_condition?(record[key.to_sym], value) }
            end.map(&:dup)
          end

          # Execute a raw query (simplified implementation)
          # @param query [String] the query to execute
          # @param params [Array] query parameters (not used in memory adapter)
          # @return [Array] empty array (placeholder implementation)
          def execute(_query, _params = [])
            ensure_connected!
            # Memory adapter doesn't support raw SQL queries
            # This is a placeholder for interface compliance
            []
          end

          # Count records matching conditions
          # @param table_name [String, Symbol] the table name
          # @param conditions [Hash] the search conditions
          # @return [Integer] the count of matching records
          def count(table_name, conditions = {})
            ensure_connected!
            ensure_table_exists(table_name)

            if conditions.empty?
              get_table(table_name).length
            else
              find_by(table_name, conditions).length
            end
          end

          # Begin a transaction (simplified for memory adapter)
          # @yield block to execute within transaction
          # @return [Object] the result of the block
          def transaction
            raise ArgumentError, 'Transaction requires a block' unless block_given?

            @transaction_level += 1

            # Simple transaction: backup data at start of top-level transaction
            @transaction_data = Marshal.load(Marshal.dump(@data)) if @transaction_level == 1

            begin
              result = yield
              # Commit: keep the changes
              @transaction_data = nil if @transaction_level == 1
              result
            rescue StandardError
              # Rollback: restore backup data
              if @transaction_level == 1
                @data = @transaction_data
                @transaction_data = nil
              end
              raise
            ensure
              @transaction_level -= 1
            end
          end

          private

          # Get the table array for a given table name
          # @param table_name [String, Symbol] the table name
          # @return [Array] the table array
          def get_table(table_name)
            @data[table_name.to_sym]
          end

          # Ensure the table exists in the data store
          # @param table_name [String, Symbol] the table name
          def ensure_table_exists(table_name)
            @data[table_name.to_sym] ||= []
          end

          # Generate a new unique id for a record
          # @param table_name [String, Symbol] the table name
          # @return [Integer] the new id
          def generate_id(table_name)
            table = get_table(table_name)
            max_id = table.map { |record| record[:id] }.compact.max || 0
            max_id + 1
          end

          # Find a record by id within a table
          # @param table_name [String, Symbol] the table name
          # @param id [Object] the record id
          # @return [Hash, nil] the record or nil if not found
          def find_record_by_id(table_name, id)
            get_table(table_name).find { |record| record[:id] == id }
          end

          # Check if a record field matches a condition value
          # @param field_value [Object] the field value
          # @param condition_value [Object] the condition value
          # @return [Boolean] true if they match
          def matches_condition?(field_value, condition_value)
            case condition_value
            when Array
              condition_value.include?(field_value)
            when Range
              condition_value.cover?(field_value)
            when Regexp
              field_value.to_s.match?(condition_value)
            else
              field_value == condition_value
            end
          end

          # Ensure the adapter is connected
          # @raise [PersistenceError] if not connected
          def ensure_connected!
            raise PersistenceError, 'Adapter is not connected' unless connected?
          end
        end

        # Class methods for persistence-enabled models
        module ClassMethods
          # Configure the persistence adapter for this class
          # @param adapter_name [Symbol, nil] the adapter name
          # @param config [Hash] adapter configuration
          # @return [Symbol] the adapter name
          def persistence_adapter(adapter_name = nil, config = {})
            if adapter_name
              @persistence_adapter_name = adapter_name.to_sym
              @persistence_adapter_config = config.dup
            end
            @persistence_adapter ||= Whiskey::ORM.persistence_config[:adapter]
          end

          # Get the adapter configuration for this class
          # @return [Hash] the adapter configuration
          def adapter_config
            @adapter_config ||= Whiskey::ORM.persistence_config[:config]
          end

          # Get the configured adapter instance for this class
          # @return [BaseAdapter] the adapter instance
          # @raise [AdapterError] if adapter is not found or fails to initialize
          def adapter
            @adapter ||= begin
              adapter_class = AdapterRegistry.get(persistence_adapter)
              adapter_instance = adapter_class.new(adapter_config)
              adapter_instance.connect
              adapter_instance
            rescue StandardError => e
              raise AdapterError, "Failed to initialize adapter #{persistence_adapter}: #{e.message}"
            end
          end

          # Get the table name for this class
          # @return [String] the table name (defaults to pluralized class name)
          def table_name
            @table_name ||= begin
              class_name = name.split('::').last.downcase
              "#{class_name}s" # Simple pluralization
            end
          end

          # Set the table name for this class
          # @param name [String, Symbol] the table name
          def set_table_name(name)
            @table_name = name.to_s
          end

          # Create a new record and persist it
          # @param attributes [Hash] the record attributes
          # @return [Object, nil] the created instance or nil if creation failed
          def create(attributes = {})
            instance = new(attributes)
            instance.drink ? instance : nil
          rescue StandardError => e
            raise PersistenceError, "Failed to create record: #{e.message}"
          end

          # Create a new record and persist it (raises on failure)
          # @param attributes [Hash] the record attributes
          # @return [Object] the created instance
          # @raise [PersistenceError] if creation fails
          def create!(attributes = {})
            instance = new(attributes)
            instance.drink! ? instance : raise(PersistenceError, 'Failed to create record')
          end

          # Find all records for this class
          # @return [Array] array of model instances
          def all
            adapter.find_by(table_name, {}).map { |attrs| new(attrs) }
          rescue StandardError => e
            raise PersistenceError, "Failed to find all records: #{e.message}"
          end

          # Find a record by id
          # @param id [Object] the record id
          # @return [Object, nil] the model instance or nil if not found
          def find(id)
            attrs = adapter.find(table_name, id)
            attrs ? new(attrs) : nil
          rescue StandardError => e
            raise PersistenceError, "Failed to find record with id #{id}: #{e.message}"
          end

          # Find a record by id (raises if not found)
          # @param id [Object] the record id
          # @return [Object] the model instance
          # @raise [RecordNotFoundError] if record is not found
          def find!(id)
            find(id) || raise(RecordNotFoundError, "Record with id #{id} not found in #{table_name}")
          end

          # Find records by conditions
          # @param conditions [Hash] the search conditions
          # @return [Array] array of matching model instances
          def where(conditions)
            adapter.find_by(table_name, conditions).map { |attrs| new(attrs) }
          rescue StandardError => e
            raise PersistenceError, "Failed to find records with conditions #{conditions}: #{e.message}"
          end

          # Find first record by conditions
          # @param conditions [Hash] the search conditions
          # @return [Object, nil] the first matching instance or nil
          def find_by(conditions)
            where(conditions).first
          end

          # Count records
          # @param conditions [Hash] optional conditions to filter the count
          # @return [Integer] the count of records
          def count(conditions = {})
            adapter.count(table_name, conditions)
          rescue StandardError => e
            raise PersistenceError, "Failed to count records: #{e.message}"
          end

          # Check if any records exist
          # @param conditions [Hash] optional conditions to check
          # @return [Boolean] true if records exist
          def exists?(conditions = {})
            adapter.exists?(table_name, conditions)
          rescue StandardError => e
            raise PersistenceError, "Failed to check existence: #{e.message}"
          end

          # Execute a database transaction
          # @yield block to execute within transaction
          # @return [Object] the result of the block
          def transaction(&block)
            adapter.transaction(&block)
          rescue StandardError => e
            raise PersistenceError, "Transaction failed: #{e.message}"
          end
        end

        # Instance methods for persistence-enabled objects
        module InstanceMethods
          # Override drink to persist the object to the database
          # @return [Boolean] true if persistence succeeded
          def drink
            return false unless valid_for_persistence?

            begin
              if new_record?
                insert_record
              else
                update_record
              end
            rescue StandardError => e
              # Let specific persistence errors bubble up, catch others
              raise e if e.is_a?(PersistenceError)

              raise PersistenceError, "Failed to persist: #{e.message}"
            end
          end

          # Persist the object to database (raises on failure)
          # @return [Boolean] true if persistence succeeded
          # @raise [PersistenceError] if persistence fails
          def drink!
            result = drink
            raise PersistenceError, 'Failed to persist record' unless result

            result
          end

          # Delete the record from the database
          # @return [Boolean] true if deletion succeeded
          def destroy
            return false if new_record?

            begin
              success = self.class.adapter.delete(self.class.table_name, id)
              if success
                @attributes[:id] = nil
                @drunk_at = nil
                true
              else
                false
              end
            rescue StandardError => e
              raise PersistenceError, "Failed to destroy record: #{e.message}"
            end
          end

          # Delete the record from database (raises on failure)
          # @return [Boolean] true if deletion succeeded
          # @raise [PersistenceError] if destruction fails
          def destroy!
            result = destroy
            raise PersistenceError, 'Failed to destroy record' unless result

            result
          end

          # Check if this is a new record (not yet persisted)
          # @return [Boolean] true if this is a new record
          def new_record?
            @attributes[:id].nil?
          end

          # Check if this record has been persisted to database
          # @return [Boolean] true if the record is persisted
          def persisted?
            !new_record? && drunk?
          end

          # Get the record id
          # @return [Object, nil] the record id or nil for new records
          def id
            @attributes[:id]
          end

          # Set the record id (for internal use)
          # @param value [Object] the id value
          def id=(value)
            @attributes[:id] = value
          end

          # Reload the record from the database
          # @return [self] returns self for chaining
          # @raise [RecordNotFoundError] if record no longer exists
          # @raise [PersistenceError] if reload fails
          def reload
            raise PersistenceError, 'Cannot reload a new record' if new_record?

            begin
              fresh_attrs = self.class.adapter.find(self.class.table_name, id)
              raise RecordNotFoundError, "Record with id #{id} no longer exists" unless fresh_attrs

              @attributes = fresh_attrs
              mark_as_drunk!
              self
            rescue RecordNotFoundError
              raise
            rescue StandardError => e
              raise PersistenceError, "Failed to reload record: #{e.message}"
            end
          end

          # Check if the record has been drunk (persisted) since filling
          # @return [Boolean] true if record has been drunk
          def drunk?
            !@drunk_at.nil?
          end

          # Get the timestamp when the record was last persisted
          # @return [Time, nil] the drunk timestamp or nil if never drunk
          def drunk_at
            @drunk_at
          end

          # Get the created_at timestamp if available
          # @return [Time, nil] the created_at timestamp
          def created_at
            @attributes[:created_at]
          end

          # Get the updated_at timestamp if available
          # @return [Time, nil] the updated_at timestamp
          def updated_at
            @attributes[:updated_at]
          end

          private

          # Check if the record is valid for persistence
          # @return [Boolean] true if valid for persistence
          def valid_for_persistence?
            # Check if validations module is enabled and validate if so
            if respond_to?(:valid?)
              valid?
            else
              filled?
            end
          end

          # Insert a new record into the database
          # @return [Boolean] true if insert succeeded
          def insert_record
            result = self.class.adapter.insert(self.class.table_name, @attributes)
            if result
              @attributes.merge!(result)
              mark_as_drunk!
              true
            else
              false
            end
          end

          # Update an existing record in the database
          # @return [Boolean] true if update succeeded
          def update_record
            result = self.class.adapter.update(self.class.table_name, id, @attributes)
            if result
              @attributes.merge!(result)
              mark_as_drunk!
              true
            else
              false
            end
          end

          # Mark the record as having been drunk (persisted)
          def mark_as_drunk!
            @drunk_at = Time.now
          end
        end

        # Register the default memory adapter when the module loads
        AdapterRegistry.register(:memory, MemoryAdapter)

        # Custom exceptions for persistence operations
        class PersistenceError < StandardError; end
        class AdapterError < StandardError; end
        class RecordNotFoundError < StandardError; end
      end
    end
  end
end
