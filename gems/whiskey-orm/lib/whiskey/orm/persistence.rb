# frozen_string_literal: true

module Whiskey
  module ORM
    # Optional persistence module for Glass objects
    # Provides pluggable database adapters and drink mechanism
    module Persistence
      def self.included(base)
        base.extend(ClassMethods)
        base.include(InstanceMethods)
      end

      # Registry for database adapters
      class AdapterRegistry
        class << self
          def adapters
            @adapters ||= {}
          end

          def register(name, adapter_class)
            adapters[name.to_sym] = adapter_class
          end

          def get(name)
            adapters[name.to_sym] || raise(AdapterError, "Unknown adapter: #{name}")
          end

          def available_adapters
            adapters.keys
          end
        end
      end

      # Base adapter class that all database adapters should inherit from
      class BaseAdapter
        attr_reader :config

        def initialize(config = {})
          @config = config
        end

        # Connect to the database
        def connect
          raise NotImplementedError, "Subclasses must implement #connect"
        end

        # Disconnect from the database
        def disconnect
          raise NotImplementedError, "Subclasses must implement #disconnect"
        end

        # Check if connected
        def connected?
          raise NotImplementedError, "Subclasses must implement #connected?"
        end

        # Insert a record
        def insert(table_name, attributes)
          raise NotImplementedError, "Subclasses must implement #insert"
        end

        # Update a record
        def update(table_name, id, attributes)
          raise NotImplementedError, "Subclasses must implement #update"
        end

        # Delete a record
        def delete(table_name, id)
          raise NotImplementedError, "Subclasses must implement #delete"
        end

        # Find a record by id
        def find(table_name, id)
          raise NotImplementedError, "Subclasses must implement #find"
        end

        # Find records by conditions
        def find_by(table_name, conditions)
          raise NotImplementedError, "Subclasses must implement #find_by"
        end

        # Execute a query
        def execute(query, params = [])
          raise NotImplementedError, "Subclasses must implement #execute"
        end

        # Count records
        def count(table_name, conditions = {})
          raise NotImplementedError, "Subclasses must implement #count"
        end

        # Check if a record exists
        def exists?(table_name, conditions)
          count(table_name, conditions) > 0
        end
      end

      # Simple in-memory adapter for testing/development
      class MemoryAdapter < BaseAdapter
        def initialize(config = {})
          super
          @data = {}
          @connected = false
        end

        def connect
          @connected = true
        end

        def disconnect
          @connected = false
        end

        def connected?
          @connected
        end

        def insert(table_name, attributes)
          ensure_table_exists(table_name)
          id = generate_id(table_name)
          record = attributes.merge(id: id)
          @data[table_name] << record
          record
        end

        def update(table_name, id, attributes)
          ensure_table_exists(table_name)
          record = find(table_name, id)
          return nil unless record
          
          record.merge!(attributes)
          record
        end

        def delete(table_name, id)
          ensure_table_exists(table_name)
          @data[table_name].reject! { |record| record[:id] == id }
        end

        def find(table_name, id)
          ensure_table_exists(table_name)
          @data[table_name].find { |record| record[:id] == id }
        end

        def find_by(table_name, conditions)
          ensure_table_exists(table_name)
          @data[table_name].select do |record|
            conditions.all? { |key, value| record[key.to_sym] == value }
          end
        end

        def execute(query, params = [])
          # Simple query execution for memory adapter
          # This is a placeholder - real adapters would parse and execute SQL
          []
        end

        def count(table_name, conditions = {})
          if conditions.empty?
            ensure_table_exists(table_name)
            @data[table_name].length
          else
            find_by(table_name, conditions).length
          end
        end

        private

        def ensure_table_exists(table_name)
          @data[table_name] ||= []
        end

        def generate_id(table_name)
          ensure_table_exists(table_name)
          (@data[table_name].map { |r| r[:id] }.compact.max || 0) + 1
        end
      end

      module ClassMethods
        # Configure persistence adapter
        def persistence_adapter(adapter_name = nil, config = {})
          if adapter_name
            @persistence_adapter_name = adapter_name.to_sym
            @persistence_adapter_config = config
          else
            @persistence_adapter_name ||= :memory
          end
        end

        # Get the configured adapter instance
        def adapter
          @adapter ||= begin
            adapter_class = AdapterRegistry.get(persistence_adapter)
            adapter_class.new(@persistence_adapter_config || {})
          end
        end

        # Create a new record
        def create(attributes = {})
          instance = new(attributes)
          instance.drink ? instance : nil
        end

        # Create a new record (with bang - raises on failure)
        def create!(attributes = {})
          instance = new(attributes)
          instance.drink! ? instance : raise(PersistenceError, "Failed to create record")
        end

        # Find all records
        def all
          adapter.find_by(table_name, {}).map { |attrs| new(attrs) }
        end

        # Find a record by id
        def find(id)
          attrs = adapter.find(table_name, id)
          attrs ? new(attrs) : nil
        end

        # Find a record by id (with bang - raises if not found)
        def find!(id)
          find(id) || raise(RecordNotFoundError, "Record with id #{id} not found")
        end
      end

      module InstanceMethods
        # Override drink to persist to database
        def drink
          return false unless valid_for_persistence?
          
          begin
            if new_record?
              result = self.class.adapter.insert(self.class.table_name, @attributes)
              if result
                @attributes.merge!(result)
                mark_as_drunk!
                true
              else
                false
              end
            else
              result = self.class.adapter.update(self.class.table_name, id, @attributes)
              if result
                mark_as_drunk!
                true
              else
                false
              end
            end
          rescue => e
            raise PersistenceError, "Failed to persist: #{e.message}"
          end
        end

        # Drink with bang (raises on failure)
        def drink!
          drink || raise(PersistenceError, "Failed to persist record")
        end

        # Delete the record
        def destroy
          return false if new_record?
          
          begin
            self.class.adapter.delete(self.class.table_name, id)
            @attributes[:id] = nil
            true
          rescue => e
            raise PersistenceError, "Failed to destroy: #{e.message}"
          end
        end

        # Delete with bang (raises on failure)
        def destroy!
          destroy || raise(PersistenceError, "Failed to destroy record")
        end

        # Check if this is a new record (not persisted yet)
        def new_record?
          @attributes[:id].nil?
        end

        # Check if this is a persisted record
        def persisted?
          !new_record? && drunk?
        end

        # Get the record id
        def id
          @attributes[:id]
        end

        # Reload the record from database
        def reload
          return self if new_record?
          
          fresh_attrs = self.class.adapter.find(self.class.table_name, id)
          if fresh_attrs
            @attributes = fresh_attrs
            mark_as_drunk!
            self
          else
            raise RecordNotFoundError, "Record no longer exists"
          end
        end

        private

        def valid_for_persistence?
          # Check if validations module is enabled and validate if so
          if respond_to?(:valid?)
            valid?
          else
            filled?
          end
        end
      end

      # Register the default memory adapter
      AdapterRegistry.register(:memory, MemoryAdapter)

      # Custom exceptions
      class PersistenceError < StandardError; end
      class AdapterError < StandardError; end
      class RecordNotFoundError < StandardError; end
    end
  end
end
