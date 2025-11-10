# frozen_string_literal: true

module Whiskey
  module ORM
    module Ingredients
      # Optional query ingredient for Glass objects
      # Provides chainable query DSL for filtering, ordering, and limits
      module Query
        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          # Start a new query chain
          def where(conditions = {})
            QueryBuilder.new(self).where(conditions)
          end

          # Order results
          def order(field, direction = :asc)
            QueryBuilder.new(self).order(field, direction)
          end

          # Limit results
          def limit(count)
            QueryBuilder.new(self).limit(count)
          end

          # Offset results
          def offset(count)
            QueryBuilder.new(self).offset(count)
          end

          # Select specific fields
          def select(*fields)
            QueryBuilder.new(self).select(*fields)
          end

          # Find all records
          def all
            QueryBuilder.new(self).all
          end

          # Find first record
          def first
            QueryBuilder.new(self).first
          end

          # Find last record
          def last
            QueryBuilder.new(self).last
          end

          # Find by id
          def find(id)
            QueryBuilder.new(self).find(id)
          end

          # Find by conditions
          def find_by(conditions)
            QueryBuilder.new(self).find_by(conditions)
          end

          # Count records
          def count
            QueryBuilder.new(self).count
          end
        end

        # Query builder class for constructing and executing queries
        class QueryBuilder
          attr_reader :model_class, :conditions, :order_clauses, :limit_value,
                      :offset_value, :select_fields

          def initialize(model_class)
            @model_class = model_class
            @conditions = {}
            @order_clauses = []
            @limit_value = nil
            @offset_value = nil
            @select_fields = []
          end

          # Add WHERE conditions
          def where(conditions = {})
            new_builder = dup
            if conditions.is_a?(Hash)
              new_builder.conditions.merge!(conditions)
            elsif conditions.is_a?(String)
              # Raw SQL condition (for advanced usage)
              new_builder.conditions[:raw] ||= []
              new_builder.conditions[:raw] << conditions
            end
            new_builder
          end

          # Add ORDER BY clause
          def order(field, direction = :asc)
            new_builder = dup
            direction = direction.to_sym
            raise ArgumentError, 'Direction must be :asc or :desc' unless %i[asc desc].include?(direction)

            new_builder.order_clauses << { field: field.to_sym, direction: direction }
            new_builder
          end

          # Add LIMIT clause
          def limit(count)
            new_builder = dup
            new_builder.limit_value = count.to_i
            new_builder
          end

          # Add OFFSET clause
          def offset(count)
            new_builder = dup
            new_builder.offset_value = count.to_i
            new_builder
          end

          # Add SELECT fields
          def select(*fields)
            new_builder = dup
            new_builder.select_fields = fields.flatten.map(&:to_sym)
            new_builder
          end

          # Execute query and return all results
          def all
            execute_query(:all)
          end

          # Execute query and return first result
          def first
            limit(1).execute_query(:first)
          end

          # Execute query and return last result
          def last
            # This would require ORDER BY id DESC LIMIT 1 in real implementation
            limit(1).execute_query(:last)
          end

          # Find by id
          def find(id)
            where(id: id).first
          end

          # Find by conditions (returns first match)
          def find_by(conditions)
            where(conditions).first
          end

          # Count matching records
          def count
            execute_query(:count)
          end

          # Check if any records match
          def exists?
            count.positive?
          end

          # Iterate over results
          def each(&block)
            all.each(&block)
          end

          # Convert to array
          def to_a
            all
          end

          # Get SQL representation (for debugging)
          def to_sql
            build_sql_query
          end

          private

          def dup
            new_builder = self.class.new(@model_class)
            new_builder.instance_variable_set(:@conditions, @conditions.dup)
            new_builder.instance_variable_set(:@order_clauses, @order_clauses.dup)
            new_builder.instance_variable_set(:@limit_value, @limit_value)
            new_builder.instance_variable_set(:@offset_value, @offset_value)
            new_builder.instance_variable_set(:@select_fields, @select_fields.dup)
            new_builder
          end

          def execute_query(type)
            # This requires persistence module for actual database execution
            unless Whiskey::ORM.enabled?(:persistence)
              case type
              when :all
                return []
              when :first, :last
                return nil
              when :count
                return 0
              end
            end

            # TODO: Implement actual query execution with persistence adapter
            # For now, return placeholder values
            case type
            when :all
              []
            when :first, :last
              nil
            when :count
              0
            end
          end

          def build_sql_query
            # Build a SQL representation for debugging purposes
            sql_parts = []

            # SELECT clause
            sql_parts << if @select_fields.empty?
                           'SELECT *'
                         else
                           "SELECT #{@select_fields.join(', ')}"
                         end

            # FROM clause
            table_name = @model_class.respond_to?(:table_name) ? @model_class.table_name : 'unknown'
            sql_parts << "FROM #{table_name}"

            # WHERE clause
            unless @conditions.empty?
              where_parts = []
              @conditions.each do |key, value|
                if key == :raw
                  where_parts.concat(Array(value))
                else
                  where_parts << if value.is_a?(Array)
                                   "#{key} IN (#{value.map { |v| quote_value(v) }.join(', ')})"
                                 else
                                   "#{key} = #{quote_value(value)}"
                                 end
                end
              end
              sql_parts << "WHERE #{where_parts.join(' AND ')}" unless where_parts.empty?
            end

            # ORDER BY clause
            unless @order_clauses.empty?
              order_parts = @order_clauses.map { |clause| "#{clause[:field]} #{clause[:direction].to_s.upcase}" }
              sql_parts << "ORDER BY #{order_parts.join(', ')}"
            end

            # LIMIT clause
            sql_parts << "LIMIT #{@limit_value}" if @limit_value

            # OFFSET clause
            sql_parts << "OFFSET #{@offset_value}" if @offset_value

            sql_parts.join(' ')
          end

          def quote_value(value)
            case value
            when String
              "'#{value.gsub("'", "''")}'"
            when nil
              'NULL'
            when true
              'TRUE'
            when false
              'FALSE'
            else
              value.to_s
            end
          end
        end
      end
    end
  end
end
