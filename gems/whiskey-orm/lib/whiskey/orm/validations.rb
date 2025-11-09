# frozen_string_literal: true

module Whiskey
  module ORM
    # Optional validations module for Glass objects
    # Provides declarative validation methods (presence, uniqueness, length, format)
    module Validations
      def self.included(base)
        base.extend(ClassMethods)
        base.prepend(InstanceMethods)
      end

      module ClassMethods
        # Store validation rules for this class
        def validations
          @validations ||= []
        end

        # Validate presence of an attribute
        def validates_presence_of(*attributes, message: "can't be blank")
          attributes.each do |attr|
            validations << {
              type: :presence,
              attribute: attr.to_sym,
              message: message
            }
          end
        end

        # Validate uniqueness of an attribute (requires persistence module)
        def validates_uniqueness_of(*attributes, message: "must be unique")
          attributes.each do |attr|
            validations << {
              type: :uniqueness,
              attribute: attr.to_sym,
              message: message
            }
          end
        end

        # Validate length of an attribute
        def validates_length_of(*attributes, minimum: nil, maximum: nil, is: nil, message: nil)
          attributes.each do |attr|
            validation = {
              type: :length,
              attribute: attr.to_sym,
              minimum: minimum,
              maximum: maximum,
              is: is
            }
            
            validation[:message] = message || build_length_message(minimum, maximum, is)
            validations << validation
          end
        end

        # Validate format of an attribute with regex
        def validates_format_of(*attributes, with:, message: "has invalid format")
          attributes.each do |attr|
            validations << {
              type: :format,
              attribute: attr.to_sym,
              pattern: with,
              message: message
            }
          end
        end

        private

        def build_length_message(minimum, maximum, is)
          if is
            "must be exactly #{is} characters long"
          elsif minimum && maximum
            "must be between #{minimum} and #{maximum} characters long"
          elsif minimum
            "must be at least #{minimum} characters long"
          elsif maximum
            "must be no more than #{maximum} characters long"
          else
            "has invalid length"
          end
        end
      end

      module InstanceMethods
        attr_reader :validation_errors

        def initialize(attributes = {})
          @validation_errors = {}
          super(attributes)
        end

        # Override drink to validate before persisting
        def drink
          return false unless valid?
          super
        end

        # Check if the glass is valid
        def valid?
          @validation_errors.clear
          run_validations
          @validation_errors.empty?
        end

        # Get validation errors for a specific attribute
        def errors_for(attribute)
          @validation_errors[attribute.to_sym] || []
        end

        # Check if there are any validation errors
        def has_errors?
          !@validation_errors.empty?
        end

        private

        def run_validations
          self.class.validations.each do |validation|
            case validation[:type]
            when :presence
              validate_presence(validation)
            when :uniqueness
              validate_uniqueness(validation)
            when :length
              validate_length(validation)
            when :format
              validate_format(validation)
            end
          end
        end

        def validate_presence(validation)
          attr = validation[:attribute]
          value = @attributes[attr]
          
          if value.nil? || (value.respond_to?(:empty?) && value.empty?)
            add_error(attr, validation[:message])
          end
        end

        def validate_uniqueness(validation)
          # This requires persistence module to check database
          # For now, just skip if persistence is not enabled
          return unless Whiskey::ORM.enabled?(:persistence)
          
          attr = validation[:attribute]
          value = @attributes[attr]
          return if value.nil?
          
          # TODO: Implement uniqueness check with persistence adapter
          # This would require querying the database for existing records
        end

        def validate_length(validation)
          attr = validation[:attribute]
          value = @attributes[attr]
          return if value.nil?
          
          length = value.to_s.length
          
          if validation[:is] && length != validation[:is]
            add_error(attr, validation[:message])
          elsif validation[:minimum] && length < validation[:minimum]
            add_error(attr, validation[:message])
          elsif validation[:maximum] && length > validation[:maximum]
            add_error(attr, validation[:message])
          end
        end

        def validate_format(validation)
          attr = validation[:attribute]
          value = @attributes[attr]
          return if value.nil?
          
          unless value.to_s.match?(validation[:pattern])
            add_error(attr, validation[:message])
          end
        end

        def add_error(attribute, message)
          @validation_errors[attribute] ||= []
          @validation_errors[attribute] << message
        end
      end
    end
  end
end
