# frozen_string_literal: true

require 'json'

module Whiskey
  module ORM
    module Ingredients
      # Optional serialization ingredient for Glass objects
      # Provides methods for converting Glass objects to JSON, XML, YAML
      module Serialization
        def self.included(base)
          base.include(InstanceMethods)
          base.extend(ClassMethods)
        end

        module ClassMethods
          # Configure serialization options for this class
          def serialization_options
            @serialization_options ||= {
              include: [],
              exclude: [],
              methods: [],
              associations: []
            }
          end

          # Configure what to include in serialization
          def serialize_with(options = {})
            serialization_options.merge!(options)
          end

          # Parse from JSON string
          def from_json(json_string)
            data = JSON.parse(json_string, symbolize_names: true)
            new(data)
          rescue JSON::ParserError => e
            raise SerializationError, "Invalid JSON: #{e.message}"
          end

          # Parse from YAML string (if YAML is available)
          def from_yaml(yaml_string)
            require 'yaml'
            data = YAML.safe_load(yaml_string, symbolize_names: true)
            new(data)
          rescue LoadError
            raise SerializationError, 'YAML library not available'
          rescue StandardError => e
            raise SerializationError, "Invalid YAML: #{e.message}"
          end
        end

        module InstanceMethods
          # Convert to JSON
          def to_json(options = {})
            to_hash(options).to_json
          end

          # Convert to pretty JSON
          def to_pretty_json(options = {})
            JSON.pretty_generate(to_hash(options))
          end

          # Convert to YAML (if YAML is available)
          def to_yaml(options = {})
            require 'yaml'
            to_hash(options).to_yaml
          rescue LoadError
            raise SerializationError, 'YAML library not available'
          end

          # Convert to XML (basic implementation)
          def to_xml(options = {})
            hash = to_hash(options)
            root_name = options[:root] || self.class.name.split('::').last.downcase

            xml = ['<?xml version="1.0" encoding="UTF-8"?>']
            xml << "<#{root_name}>"
            xml << hash_to_xml_elements(hash, 1)
            xml << "</#{root_name}>"

            xml.join("\n")
          end

          # Convert to hash with serialization options
          def to_hash(options = {})
            # Merge class-level options with instance-level options
            opts = self.class.serialization_options.merge(options)

            result = {}

            # Start with all attributes
            attrs_to_include = @attributes.dup

            # Apply include filter (if specified, only include these)
            if opts[:include] && !opts[:include].empty?
              attrs_to_include = attrs_to_include.select { |key, _| opts[:include].include?(key) }
            end

            # Apply exclude filter
            if opts[:exclude] && !opts[:exclude].empty?
              attrs_to_include = attrs_to_include.reject { |key, _| opts[:exclude].include?(key) }
            end

            result.merge!(attrs_to_include)

            # Add custom methods
            if opts[:methods] && !opts[:methods].empty?
              opts[:methods].each do |method_name|
                result[method_name] = send(method_name) if respond_to?(method_name)
              end
            end

            # Add associations (if associations module is enabled)
            if opts[:associations] && !opts[:associations].empty? && respond_to?(:association_names)
              opts[:associations].each do |assoc_name|
                if association_names.include?(assoc_name.to_sym)
                  assoc_value = send(assoc_name)
                  result[assoc_name] = serialize_association_value(assoc_value)
                end
              end
            end

            # Add metadata if requested
            if opts[:include_metadata]
              result[:_metadata] = {
                class_name: self.class.name,
                filled_at: @filled_at,
                drunk_at: @drunk_at,
                filled: filled?,
                drunk: drunk?
              }
            end

            result
          end

          # Serialize with specific format
          def serialize(format = :json, options = {})
            case format.to_sym
            when :json
              to_json(options)
            when :pretty_json
              to_pretty_json(options)
            when :yaml
              to_yaml(options)
            when :xml
              to_xml(options)
            when :hash
              to_hash(options)
            else
              raise SerializationError, "Unsupported format: #{format}"
            end
          end

          # Update attributes from serialized data
          def fill_from_json(json_string)
            data = JSON.parse(json_string, symbolize_names: true)
            fill(data)
          rescue JSON::ParserError => e
            raise SerializationError, "Invalid JSON: #{e.message}"
          end

          def fill_from_yaml(yaml_string)
            require 'yaml'
            data = YAML.safe_load(yaml_string, symbolize_names: true)
            fill(data)
          rescue LoadError
            raise SerializationError, 'YAML library not available'
          rescue StandardError => e
            raise SerializationError, "Invalid YAML: #{e.message}"
          end

          private

          def serialize_association_value(value)
            case value
            when Array
              value.map { |item| serialize_single_association_item(item) }
            else
              serialize_single_association_item(value)
            end
          end

          def serialize_single_association_item(item)
            if item.respond_to?(:to_hash)
              item.to_hash
            elsif item.respond_to?(:attributes)
              item.attributes
            else
              item
            end
          end

          def hash_to_xml_elements(hash, indent_level = 0)
            indent = '  ' * indent_level
            elements = []

            hash.each do |key, value|
              case value
              when Hash
                elements << "#{indent}<#{key}>"
                elements << hash_to_xml_elements(value, indent_level + 1)
                elements << "#{indent}</#{key}>"
              when Array
                value.each do |item|
                  if item.is_a?(Hash)
                    elements << "#{indent}<#{key}>"
                    elements << hash_to_xml_elements(item, indent_level + 1)
                    elements << "#{indent}</#{key}>"
                  else
                    elements << "#{indent}<#{key}>#{xml_escape(item)}</#{key}>"
                  end
                end
              else
                elements << "#{indent}<#{key}>#{xml_escape(value)}</#{key}>"
              end
            end

            elements.join("\n")
          end

          def xml_escape(value)
            return '' if value.nil?

            value.to_s
                 .gsub('&', '&amp;')
                 .gsub('<', '&lt;')
                 .gsub('>', '&gt;')
                 .gsub('"', '&quot;')
                 .gsub("'", '&apos;')
          end
        end

        # Custom exception for serialization errors
        class SerializationError < StandardError; end
      end
    end
  end
end
