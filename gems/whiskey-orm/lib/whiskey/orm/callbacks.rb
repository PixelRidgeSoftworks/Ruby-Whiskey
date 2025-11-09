# frozen_string_literal: true

module Whiskey
  module ORM
    # Optional callbacks module for Glass objects
    # Provides lifecycle hooks (before_fill, after_drink, around_drink, etc.)
    module Callbacks
      def self.included(base)
        base.extend(ClassMethods)
        base.include(InstanceMethods)
      end

      module ClassMethods
        # Store callback definitions for this class
        def callbacks
          @callbacks ||= {
            before_fill: [],
            after_fill: [],
            around_fill: [],
            before_drink: [],
            after_drink: [],
            around_drink: [],
            before_empty: [],
            after_empty: [],
            around_empty: []
          }
        end

        # Define before_fill callback
        def before_fill(*method_names, &block)
          add_callback(:before_fill, method_names, block)
        end

        # Define after_fill callback
        def after_fill(*method_names, &block)
          add_callback(:after_fill, method_names, block)
        end

        # Define around_fill callback
        def around_fill(*method_names, &block)
          add_callback(:around_fill, method_names, block)
        end

        # Define before_drink callback
        def before_drink(*method_names, &block)
          add_callback(:before_drink, method_names, block)
        end

        # Define after_drink callback
        def after_drink(*method_names, &block)
          add_callback(:after_drink, method_names, block)
        end

        # Define around_drink callback
        def around_drink(*method_names, &block)
          add_callback(:around_drink, method_names, block)
        end

        # Define before_empty callback
        def before_empty(*method_names, &block)
          add_callback(:before_empty, method_names, block)
        end

        # Define after_empty callback
        def after_empty(*method_names, &block)
          add_callback(:after_empty, method_names, block)
        end

        # Define around_empty callback
        def around_empty(*method_names, &block)
          add_callback(:around_empty, method_names, block)
        end

        private

        def add_callback(type, method_names, block)
          if block_given?
            callbacks[type] << block
          else
            method_names.each do |method_name|
              callbacks[type] << method_name.to_sym
            end
          end
        end
      end

      module InstanceMethods
        # Override fill to add callbacks
        def fill(data)
          run_callbacks(:before_fill)
          
          result = if has_around_callbacks?(:around_fill)
                     run_around_callbacks(:around_fill) { super(data) }
                   else
                     super(data)
                   end
          
          run_callbacks(:after_fill)
          result
        end

        # Override drink to add callbacks
        def drink
          run_callbacks(:before_drink)
          
          result = if has_around_callbacks?(:around_drink)
                     run_around_callbacks(:around_drink) { super }
                   else
                     super
                   end
          
          run_callbacks(:after_drink) if result
          result
        end

        # Override empty! to add callbacks
        def empty!
          run_callbacks(:before_empty)
          
          result = if has_around_callbacks?(:around_empty)
                     run_around_callbacks(:around_empty) { super }
                   else
                     super
                   end
          
          run_callbacks(:after_empty)
          result
        end

        # Manually run a specific callback type
        def run_callback(callback_name)
          callback_sym = callback_name.to_sym
          return unless self.class.callbacks.key?(callback_sym)
          
          run_callbacks(callback_sym)
        end

        # Check if callbacks are defined for a specific type
        def has_callbacks?(type)
          callbacks = self.class.callbacks[type.to_sym]
          callbacks && !callbacks.empty?
        end

        private

        def run_callbacks(type)
          return unless has_callbacks?(type)
          
          self.class.callbacks[type].each do |callback|
            execute_callback(callback)
          end
        end

        def run_around_callbacks(type, &block)
          around_callbacks = self.class.callbacks[type] || []
          return yield if around_callbacks.empty?
          
          # Chain around callbacks
          chain = around_callbacks.reverse.reduce(block) do |inner, callback|
            proc do
              if callback.is_a?(Proc)
                callback.call(self, inner)
              else
                send(callback, inner)
              end
            end
          end
          
          chain.call
        end

        def has_around_callbacks?(type)
          callbacks = self.class.callbacks[type]
          callbacks && !callbacks.empty?
        end

        def execute_callback(callback)
          case callback
          when Symbol
            send(callback) if respond_to?(callback, true)
          when Proc
            if callback.arity == 0
              instance_eval(&callback)
            else
              callback.call(self)
            end
          when String
            send(callback.to_sym) if respond_to?(callback.to_sym, true)
          else
            raise CallbackError, "Invalid callback type: #{callback.class}"
          end
        rescue => e
          raise CallbackError, "Error executing callback #{callback}: #{e.message}"
        end
      end

      # Callback execution context for around callbacks
      class CallbackChain
        def initialize(object, callbacks, block)
          @object = object
          @callbacks = callbacks
          @block = block
          @index = 0
        end

        def call
          if @index < @callbacks.length
            callback = @callbacks[@index]
            @index += 1
            
            case callback
            when Proc
              if callback.arity == 2
                callback.call(@object, self)
              else
                @object.instance_exec(self, &callback)
              end
            when Symbol
              @object.send(callback, self)
            end
          else
            @block.call
          end
        end
      end

      # Custom exception for callback errors
      class CallbackError < StandardError; end
    end
  end
end
