# frozen_string_literal: true

require 'yaml'
require 'json'
require 'pathname'

module Whiskey
  module Core
    # Unified global configuration system for Ruby Whiskey
    # Supports .whiskey, .yaml, .yml, and .rb config files
    # Uses whiskey-themed metaphors throughout
    class Config
      # Configuration data cache
      @barrel = {}
      @config_file = nil
      @loaded = false

      class << self
        attr_reader :barrel, :config_file, :loaded

        # Load configuration from project root
        # Searches for config files in order of preference
        # @param force_reload [Boolean] whether to reload if already loaded
        # @return [Boolean] true if successfully loaded
        def load!(force_reload: false)
          return true if @loaded && !force_reload

          @config_file = find_config_file
          unless @config_file
            @barrel = {}
            @loaded = true
            return true # Empty config is valid
          end

          begin
            @barrel = parse_config_file(@config_file)
            @loaded = true
            log_info("Configuration distilled from #{@config_file}")
            true
          rescue StandardError => e
            log_error("Failed to distill configuration from #{@config_file}: #{e.message}")
            @barrel = {}
            @loaded = false
            false
          end
        end

        # Reload configuration file
        # @return [Boolean] true if successfully reloaded
        def reload!
          @loaded = false
          load!(force_reload: true)
        end

        # Access configuration values using dot notation
        # @param key_path [String] dot-separated key path (e.g., "ORM.Enabled")
        # @return [Object] the configuration value or nil
        def [](key_path)
          load! unless @loaded

          keys = key_path.split('.')
          current = @barrel

          keys.each do |key|
            return nil unless current.is_a?(Hash) && current.key?(key)

            current = current[key]
          end

          current
        end

        # Get a configuration section as a hash
        # @param section_name [Symbol, String] the section name
        # @return [Hash] the configuration section or empty hash
        def section(section_name)
          load! unless @loaded

          section_key = section_name.to_s
          return {} unless @barrel.is_a?(Hash)

          @barrel[section_key] || {}
        end

        # Check if configuration has been loaded
        # @return [Boolean] true if loaded
        def loaded?
          @loaded
        end

        # Get the path of the loaded config file
        # @return [String, nil] the config file path or nil
        def config_file_path
          @config_file
        end

        # Get all configuration data (for debugging)
        # @return [Hash] the entire configuration barrel
        def all
          load! unless @loaded
          @barrel.dup
        end

        # Set configuration value (for testing/runtime modification)
        # @param key_path [String] dot-separated key path
        # @param value [Object] the value to set
        def []=(key_path, value)
          load! unless @loaded

          keys = key_path.split('.')
          current = @barrel

          # Navigate to parent hash, creating as needed
          keys[0..-2].each do |key|
            current[key] = {} unless current.key?(key) && current[key].is_a?(Hash)
            current = current[key]
          end

          # Set the final value
          current[keys.last] = value
        end

        private

        # Find the configuration file in project root
        # @return [String, nil] path to config file or nil if not found
        def find_config_file
          root_dir = find_project_root
          return nil unless root_dir

          # Get current environment
          env = defined?(Whiskey.env) ? Whiskey.env : 'development'

          # Search for environment-specific config files first, then general ones
          config_patterns = [
            "config.whiskey.#{env}",
            "config.whiskey.#{env}.rb",
            "config.#{env}.whiskey",
            "config.#{env}.yaml",
            "config.#{env}.yml",
            'config.whiskey',
            'config.whiskey.rb',
            'config.yaml',
            'config.yml'
          ]

          config_patterns.each do |pattern|
            config_path = File.join(root_dir, pattern)
            return config_path if File.exist?(config_path)
          end

          nil
        end

        # Find the project root directory
        # Looks for Gemfile, .git, or other project markers
        # @return [String, nil] project root path or nil
        def find_project_root
          current_dir = Dir.pwd

          # Look for project markers
          markers = ['Gemfile', '.git', 'config.whiskey', 'config.yaml', 'config.yml']

          # Start from current directory and work up
          path = Pathname.new(current_dir)

          loop do
            # Check if any marker exists in current directory
            return path.to_s if markers.any? { |marker| (path + marker).exist? }

            # Move up one directory
            parent = path.parent
            break if parent == path # Reached filesystem root

            path = parent
          end

          # Default to current directory if no markers found
          current_dir
        end

        # Parse configuration file based on extension
        # @param file_path [String] path to config file
        # @return [Hash] parsed configuration data
        def parse_config_file(file_path)
          extension = File.extname(file_path)
          base_name = File.basename(file_path, extension)

          case extension
          when '.rb'
            parse_ruby_config(file_path)
          when '.yaml', '.yml'
            parse_yaml_config(file_path)
          when ''
            # Handle files like 'config.whiskey' - use natural language DSL
            if base_name.include?('.')
            end
            parse_whiskey_dsl(file_path)
          else
            parse_yaml_config(file_path) # Default to YAML
          end
        end

        # Parse YAML configuration file
        # @param file_path [String] path to YAML file
        # @return [Hash] parsed configuration
        def parse_yaml_config(file_path)
          content = File.read(file_path)
          parsed = YAML.safe_load(content, aliases: true) || {}

          raise "Configuration file must contain a hash/object, got #{parsed.class}" unless parsed.is_a?(Hash)

          parsed
        rescue Psych::SyntaxError => e
          raise "Invalid YAML in configuration file: #{e.message}"
        end

        # Parse Ruby DSL configuration file
        # @param file_path [String] path to Ruby file
        # @return [Hash] configuration built by DSL
        def parse_ruby_config(file_path)
          # Create a safe evaluation context
          dsl = ConfigDSL.new

          # Read and evaluate the Ruby configuration
          content = File.read(file_path)
          dsl.instance_eval(content, file_path)

          dsl.to_hash
        rescue StandardError => e
          raise "Error evaluating Ruby configuration: #{e.message}"
        end

        # Parse natural language Whiskey DSL configuration file
        # @param file_path [String] path to .whiskey file
        # @return [Hash] parsed configuration
        def parse_whiskey_dsl(file_path)
          content = File.read(file_path)
          parser = WhiskeyDSLParser.new
          parser.parse(content)
        rescue StandardError => e
          raise "Error parsing Whiskey DSL configuration: #{e.message}"
        end

        # Log info message
        # @param message [String] the message to log
        def log_info(message)
          if defined?(Whiskey::ORM::Log)
            Whiskey::ORM::Log.info("[Whiskey::Config] #{message}")
          elsif defined?(Rails) && Rails.logger
            Rails.logger.info("[Whiskey::Config] #{message}")
          else
            puts "[INFO] [Whiskey::Config] #{message}"
          end
        end

        # Log error message
        # @param message [String] the error message to log
        def log_error(message)
          if defined?(Whiskey::ORM::Log)
            Whiskey::ORM::Log.error("[Whiskey::Config] #{message}")
          elsif defined?(Rails) && Rails.logger
            Rails.logger.error("[Whiskey::Config] #{message}")
          else
            puts "[ERROR] [Whiskey::Config] #{message}"
          end
        end
      end

      # Ruby DSL for configuration files
      # Provides a clean, whiskey-themed DSL for Ruby config files
      class ConfigDSL
        def initialize
          @config_barrel = {}
        end

        # Convert DSL configuration to hash
        # @return [Hash] the configuration hash
        def to_hash
          @config_barrel
        end

        # Define a configuration section using whiskey metaphors
        # @param section_name [Symbol, String] the section name
        # @yield [SectionDSL] block for section configuration
        def section(section_name, &block)
          section_dsl = SectionDSL.new
          section_dsl.instance_eval(&block) if block_given?
          @config_barrel[section_name.to_s] = section_dsl.to_hash
        end

        # Alternative method names with whiskey metaphors
        alias barrel section
        alias cask section

        # Set a simple key-value pair
        # @param key [Symbol, String] the key
        # @param value [Object] the value
        def set(key, value)
          @config_barrel[key.to_s] = value
        end

        # Whiskey-themed alias for set
        alias pour set
        alias distill set

        # Handle method_missing for direct key assignment
        def method_missing(method_name, *args, &block)
          if method_name.to_s.end_with?('=')
            key = method_name.to_s.chomp('=')
            @config_barrel[key] = args.first
          elsif args.length == 1 && !block_given?
            @config_barrel[method_name.to_s] = args.first
          elsif block_given?
            section(method_name, &block)
          else
            super
          end
        end

        def respond_to_missing?(method_name, include_private = false)
          method_name.to_s.end_with?('=') || super
        end
      end

      # Section DSL for nested configuration
      class SectionDSL
        def initialize
          @section_data = {}
        end

        # Convert section to hash
        # @return [Hash] the section configuration
        def to_hash
          @section_data
        end

        # Set a key-value pair in this section
        # @param key [Symbol, String] the key
        # @param value [Object] the value
        def set(key, value)
          @section_data[key.to_s] = value
        end

        # Whiskey-themed aliases
        alias pour set
        alias add set

        # Create a nested subsection
        # @param subsection_name [Symbol, String] the subsection name
        # @yield [SectionDSL] block for subsection configuration
        def subsection(subsection_name, &block)
          subsection_dsl = SectionDSL.new
          subsection_dsl.instance_eval(&block) if block_given?
          @section_data[subsection_name.to_s] = subsection_dsl.to_hash
        end

        # Whiskey-themed aliases for nested sections
        alias ingredient subsection
        alias blend subsection

        # Handle method_missing for flexible assignment
        def method_missing(method_name, *args, &block)
          if method_name.to_s.end_with?('=')
            key = method_name.to_s.chomp('=')
            @section_data[key] = args.first
          elsif args.length == 1 && !block_given?
            @section_data[method_name.to_s] = args.first
          elsif block_given?
            subsection(method_name, &block)
          else
            super
          end
        end

        def respond_to_missing?(method_name, include_private = false)
          method_name.to_s.end_with?('=') || super
        end
      end

      # Natural language DSL parser for .whiskey files
      # Supports human-readable configuration syntax
      class WhiskeyDSLParser
        def initialize
          @config = {}
          @current_section = nil
          @indent_stack = []
        end

        # Parse the DSL content into a configuration hash
        # @param content [String] the DSL content to parse
        # @return [Hash] parsed configuration
        def parse(content)
          lines = content.split("\n")

          lines.each_with_index do |line, line_number|
            process_line(line.rstrip, line_number + 1)
          rescue StandardError => e
            raise "Parse error at line #{line_number + 1}: #{e.message}\nLine: #{line}"
          end

          @config
        end

        private

        # Process a single line of DSL
        # @param line [String] the line to process
        # @param line_number [Integer] line number for error reporting
        def process_line(line, _line_number)
          # Skip empty lines and comments
          return if line.strip.empty? || line.strip.start_with?('#')

          # Calculate indentation
          indent = line.length - line.lstrip.length
          content = line.strip

          # Handle section changes based on indentation
          handle_indentation(indent)

          # Parse different types of statements
          if section_declaration?(content)
            handle_section(content, indent)
          elsif assignment_statement?(content)
            handle_assignment(content)
          elsif list_item?(content)
            handle_list_item(content)
          elsif natural_language_statement?(content)
            handle_natural_language(content)
          else
            # Ignore unrecognized lines (could be descriptive text)
          end
        end

        # Handle indentation changes
        # @param indent [Integer] current line indentation
        def handle_indentation(indent)
          # Remove levels from stack if we've dedented
          @indent_stack.pop while @indent_stack.length.positive? && @indent_stack.last >= indent
        end

        # Check if line is a section declaration
        # @param content [String] line content
        # @return [Boolean] true if section declaration
        def section_declaration?(content)
          content.match?(/^(\w+)(?:\s+(?:barrel|cask))?:$/i)
        end

        # Handle section declarations
        # @param content [String] line content
        # @param indent [Integer] indentation level
        def handle_section(content, indent)
          # Extract section name (remove barrel/cask suffix)
          return unless content.match(/^(\w+)(?:\s+(?:barrel|cask))?:$/i)

          section_name = ::Regexp.last_match(1)




          @indent_stack << indent
          @current_section = build_section_path(section_name, indent)

          # Initialize section if it doesn't exist
          set_nested_value(@config, @current_section, {}) unless get_nested_value(@config, @current_section)
        end

        # Check if line is an assignment statement
        # @param content [String] line content
        # @return [Boolean] true if assignment
        def assignment_statement?(content)
          content.match?(/^(\w+):\s*(.+)$/i)
        end

        # Handle assignment statements
        # @param content [String] line content
        def handle_assignment(content)
          return unless content.match(/^(\w+):\s*(.+)$/i)

          key = ::Regexp.last_match(1)
          value = parse_value(::Regexp.last_match(2))

          target_path = @current_section ? @current_section + [key] : [key]
          set_nested_value(@config, target_path, value)
        end

        # Check if line is a list item
        # @param content [String] line content
        # @return [Boolean] true if list item
        def list_item?(content)
          content.match?(/^(?:-|\*)\s+(.+)$/)
        end

        # Handle list items
        # @param content [String] line content
        def handle_list_item(content)
          return unless content.match(/^(?:-|\*)\s+(.+)$/)

          item_value = parse_value(::Regexp.last_match(1).strip)

          # Find the parent for this list (last key set)
          return unless @current_section

          parent = get_nested_value(@config, @current_section)

          # Convert to array if not already
          unless parent.is_a?(Array)
            set_nested_value(@config, @current_section, [])
            parent = get_nested_value(@config, @current_section)
          end

          parent << item_value
        end

        # Check if line is natural language
        # @param content [String] line content
        # @return [Boolean] true if natural language
        def natural_language_statement?(content)
          content.match?(/^(?:Please|Should|Must|Will|Can|Let|Make)\s+/i) ||
            content.match?(/(?:enabled?|disabled?|activated?|configured?)$/i)
        end

        # Handle natural language statements
        # @param content [String] line content
        def handle_natural_language(content)
          # Extract meaningful information from natural language
          case content
          when /(?:enable|activate|turn on)\s+(\w+)/i
            key = ::Regexp.last_match(1)
            target_path = @current_section ? @current_section + [key] : [key]
            set_nested_value(@config, target_path, true)
          when /(?:disable|deactivate|turn off)\s+(\w+)/i
            key = ::Regexp.last_match(1)
            target_path = @current_section ? @current_section + [key] : [key]
            set_nested_value(@config, target_path, false)
          when /(\w+)\s+(?:is|should be|must be)\s+enabled?/i
            key = ::Regexp.last_match(1)
            target_path = @current_section ? @current_section + [key] : [key]
            set_nested_value(@config, target_path, true)
          when /(\w+)\s+(?:is|should be|must be)\s+disabled?/i
            key = ::Regexp.last_match(1)
            target_path = @current_section ? @current_section + [key] : [key]
            set_nested_value(@config, target_path, false)
          end
        end

        # Build section path based on current nesting
        # @param section_name [String] name of the section
        # @param indent [Integer] current indentation level
        # @return [Array<String>] path components
        def build_section_path(section_name, _indent)
          path = []

          # Build path based on indentation stack
          # For now, simple approach - just use the section name
          # Could be extended to support nested paths based on indentation
          path << section_name

          path
        end

        # Parse a value string into appropriate Ruby type
        # @param value_str [String] the value string
        # @return [Object] parsed value
        def parse_value(value_str)
          value_str = value_str.strip

          # Handle boolean values
          case value_str.downcase
          when 'true', 'yes', 'on', 'enabled', 'enable'
            return true
          when 'false', 'no', 'off', 'disabled', 'disable'
            return false
          when 'null', 'nil', 'none'
            return nil
          end

          # Handle quoted strings
          return ::Regexp.last_match(1) if value_str.match(/^["'](.*)["']$/)

          # Handle numbers
          if value_str.match(/^\d+$/)
            return value_str.to_i
          elsif value_str.match(/^\d+\.\d+$/)
            return value_str.to_f
          end

          # Handle arrays (comma-separated)
          return value_str.split(',').map { |item| parse_value(item.strip) } if value_str.include?(',')

          # Default to string
          value_str
        end

        # Set a nested value in a hash structure
        # @param hash [Hash] the hash to modify
        # @param path [Array<String>] path components
        # @param value [Object] value to set
        def set_nested_value(hash, path, value)
          current = hash

          path[0..-2].each do |key|
            current[key] = {} unless current[key].is_a?(Hash)
            current = current[key]
          end

          current[path.last] = value
        end

        # Get a nested value from a hash structure
        # @param hash [Hash] the hash to read from
        # @param path [Array<String>] path components
        # @return [Object] the value or nil
        def get_nested_value(hash, path)
          current = hash

          path.each do |key|
            return nil unless current.is_a?(Hash) && current.key?(key)

            current = current[key]
          end

          current
        end
      end
    end
  end

  # Make Config available at top level for convenience
  Config = Core::Config
end
