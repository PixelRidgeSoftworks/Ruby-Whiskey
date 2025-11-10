# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Boot profiles functionality for selective subsystem loading
      module BootProfiles
        private

        # Determine which subsystems to boot based on profile
        # @param profile [Symbol, nil] the boot profile
        # @return [Hash] filtered subsystem registry
        def determine_boot_targets(profile)
          return @subsystem_registry unless profile

          # Get profile configuration
          profile_config = get_boot_profile_config(profile)
          return @subsystem_registry if profile_config.empty?

          # Filter registry based on profile
          target_names = profile_config.map(&:to_sym)
          filtered_registry = @subsystem_registry.select { |name, _| target_names.include?(name) }

          log_info("🎯 Boot profile '#{profile}' targeting: #{target_names.join(', ')}")
          filtered_registry
        end

        # Get boot profile configuration from config
        # @param profile [Symbol] the profile name
        # @return [Array<String>] subsystem names for the profile
        def get_boot_profile_config(profile)
          return [] unless defined?(Whiskey::Config) && Whiskey::Config.respond_to?(:section)

          profiles_config = Whiskey::Config.section('Profiles') || {}
          profiles_config[profile.to_s] || []
        end
      end
    end
  end
end
