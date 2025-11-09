# frozen_string_literal: true

module Whiskey
  module ORM
    # Core ORM functionality using the "Whiskey Glass" metaphor
    # Objects can be "filled" with data and "drunk" (persisted)
    module Core
      # Base Glass class - represents a data object that can be filled and drunk
      class Glass
        attr_reader :attributes, :filled_at, :drunk_at
        
        def initialize(attributes = {})
          @attributes = {}
          @filled_at = nil
          @drunk_at = nil
          fill(attributes) unless attributes.empty?
        end

        # Fill the glass with data (like loading from database or setting attributes)
        def fill(data)
          return self if data.nil? || data.empty?
          
          @attributes.merge!(data)
          @filled_at = Time.now
          self
        end

        # Check if the glass has been filled
        def filled?
          !@filled_at.nil? && !@attributes.empty?
        end

        # Check if the glass has been drunk (persisted)
        def drunk?
          !@drunk_at.nil?
        end

        # Empty the glass (clear all data)
        def empty!
          @attributes.clear
          @filled_at = nil
          @drunk_at = nil
          self
        end

        # Get an attribute value
        def [](key)
          @attributes[key.to_sym]
        end

        # Set an attribute value
        def []=(key, value)
          @attributes[key.to_sym] = value
        end

        # Get all attribute keys
        def keys
          @attributes.keys
        end

        # Check if an attribute exists
        def has_attribute?(key)
          @attributes.key?(key.to_sym)
        end

        # Convert to hash
        def to_h
          @attributes.dup
        end

        # String representation
        def to_s
          state = case
                  when drunk? then "drunk"
                  when filled? then "filled"
                  else "empty"
                  end
          "#<#{self.class.name} #{state} attributes=#{@attributes}>"
        end

        # Drink the glass (persist the data)
        # This is a basic implementation - enhanced by persistence module
        def drink
          return false unless filled?
          
          # Basic drinking behavior - mark as drunk
          @drunk_at = Time.now
          true
        end

        protected

        # Mark the glass as drunk (used by persistence adapters)
        def mark_as_drunk!
          @drunk_at = Time.now
        end
      end

      # Base model class that can be inherited from
      class Model < Glass
        class << self
          attr_accessor :table_name

          # Define the table name for this model
          def table(name)
            self.table_name = name.to_s
          end

          # Get the table name (defaults to pluralized class name)
          def table_name
            @table_name ||= "#{name.split('::').last.downcase}s"
          end
        end

        def initialize(attributes = {})
          super(attributes)
        end
      end
    end
  end
end
