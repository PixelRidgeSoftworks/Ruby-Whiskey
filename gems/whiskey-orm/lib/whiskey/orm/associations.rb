# frozen_string_literal: true

module Whiskey
  module ORM
    module Ingredients
      # Optional associations ingredient for Glass objects
      # Provides relationship methods (has_one, has_many, belongs_to)
      module Associations
        def self.included(base)
          base.extend(ClassMethods)
          base.include(InstanceMethods)
        end

        module ClassMethods
          # Store association definitions for this class
          def associations
            @associations ||= {}
          end

          # Define a has_one association
          def has_one(name, class_name: nil, foreign_key: nil, primary_key: :id)
            class_name ||= name.to_s.capitalize
            foreign_key ||= "#{self.name.split('::').last.downcase}_id"

            associations[name.to_sym] = {
              type: :has_one,
              class_name: class_name,
              foreign_key: foreign_key.to_sym,
              primary_key: primary_key.to_sym
            }

            define_association_method(name, :has_one)
          end

          # Define a has_many association
          def has_many(name, class_name: nil, foreign_key: nil, primary_key: :id)
            class_name ||= name.to_s.capitalize.chop # Remove 's' for singular
            foreign_key ||= "#{self.name.split('::').last.downcase}_id"

            associations[name.to_sym] = {
              type: :has_many,
              class_name: class_name,
              foreign_key: foreign_key.to_sym,
              primary_key: primary_key.to_sym
            }

            define_association_method(name, :has_many)
          end

          # Define a belongs_to association
          def belongs_to(name, class_name: nil, foreign_key: nil, primary_key: :id)
            class_name ||= name.to_s.capitalize
            foreign_key ||= "#{name}_id"

            associations[name.to_sym] = {
              type: :belongs_to,
              class_name: class_name,
              foreign_key: foreign_key.to_sym,
              primary_key: primary_key.to_sym
            }

            define_association_method(name, :belongs_to)
          end

          private

          def define_association_method(name, type)
            case type
            when :has_one, :belongs_to
              define_method(name) do
                load_association(name)
              end

              define_method("#{name}=") do |value|
                set_association(name, value)
              end

            when :has_many
              define_method(name) do
                load_association_collection(name)
              end

              define_method("#{name}=") do |collection|
                set_association_collection(name, collection)
              end
            end
          end
        end

        module InstanceMethods
          def initialize(attributes = {})
            @association_cache = {}
            @association_loaded = {}
            super(attributes)
          end

          # Get association names for this instance
          def association_names
            self.class.associations.keys
          end

          # Check if an association is loaded
          def association_loaded?(name)
            @association_loaded[name.to_sym] || false
          end

          # Clear association cache
          def clear_association_cache!
            @association_cache.clear
            @association_loaded.clear
          end

          private

          def load_association(name)
            return @association_cache[name] if association_loaded?(name)

            association = self.class.associations[name.to_sym]
            return nil unless association

            case association[:type]
            when :has_one
              load_has_one_association(name, association)
            when :belongs_to
              load_belongs_to_association(name, association)
            end
          end

          def load_association_collection(name)
            return @association_cache[name] if association_loaded?(name)

            association = self.class.associations[name.to_sym]
            return [] unless association

            if association[:type] == :has_many
              load_has_many_association(name, association)
            else
              []
            end
          end

          def load_has_one_association(name, association)
            # This requires persistence module for database queries
            unless Whiskey::ORM.enabled?(:persistence)
              @association_cache[name] = nil
              @association_loaded[name] = true
              return nil
            end

            # TODO: Implement database query
            # SELECT * FROM {table} WHERE {foreign_key} = {primary_key_value} LIMIT 1
            primary_key_value = @attributes[association[:primary_key]]
            return nil unless primary_key_value

            # For now, return nil as placeholder
            @association_cache[name] = nil
            @association_loaded[name] = true
            nil
          end

          def load_belongs_to_association(name, association)
            # This requires persistence module for database queries
            unless Whiskey::ORM.enabled?(:persistence)
              @association_cache[name] = nil
              @association_loaded[name] = true
              return nil
            end

            # TODO: Implement database query
            # SELECT * FROM {associated_table} WHERE {primary_key} = {foreign_key_value} LIMIT 1
            foreign_key_value = @attributes[association[:foreign_key]]
            return nil unless foreign_key_value

            # For now, return nil as placeholder
            @association_cache[name] = nil
            @association_loaded[name] = true
            nil
          end

          def load_has_many_association(name, association)
            # This requires persistence module for database queries
            unless Whiskey::ORM.enabled?(:persistence)
              @association_cache[name] = []
              @association_loaded[name] = true
              return []
            end

            # TODO: Implement database query
            # SELECT * FROM {table} WHERE {foreign_key} = {primary_key_value}
            primary_key_value = @attributes[association[:primary_key]]
            return [] unless primary_key_value

            # For now, return empty array as placeholder
            @association_cache[name] = []
            @association_loaded[name] = true
            []
          end

          def set_association(name, value)
            association = self.class.associations[name.to_sym]
            return unless association

            @association_cache[name] = value
            @association_loaded[name] = true

            # Set foreign key if belongs_to
            return unless association[:type] == :belongs_to && value
            return unless value.respond_to?(:attributes) && value.attributes[association[:primary_key]]

            @attributes[association[:foreign_key]] = value.attributes[association[:primary_key]]
          end

          def set_association_collection(name, collection)
            association = self.class.associations[name.to_sym]
            return unless association && association[:type] == :has_many

            collection = Array(collection)
            @association_cache[name] = collection
            @association_loaded[name] = true

            # Set foreign keys on associated objects if has_many
            primary_key_value = @attributes[association[:primary_key]]
            return unless primary_key_value

            collection.each do |item|
              item.attributes[association[:foreign_key]] = primary_key_value if item.respond_to?(:attributes)
            end
          end
        end
      end
    end
  end
end
