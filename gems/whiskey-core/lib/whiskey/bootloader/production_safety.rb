# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Production safety module for environment-aware protections
      # Provides safeguards against destructive operations in production environments
      module ProductionSafety
        private

        # Check if production mutation guard is active
        # @return [Boolean] true if mutations should be blocked in production
        def production_mutation_guard_active?
          Whiskey.production? && ENV['WHISKEY_ALLOW_MUTATIONS'] != 'true'
        end
      end
    end
  end
end
