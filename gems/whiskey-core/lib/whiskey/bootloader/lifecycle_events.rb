# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # DSL module for lifecycle events - mixed into subsystems
      module LifecycleEventsDSL
        # Register a lifecycle hook declaratively
        # @param phase [Symbol] the hook phase
        # @param options [Hash] hook options including target
        # @param block [Proc] the hook block to execute
        def on_boot(phase, **options, &block)
          hook_name = "#{name.downcase}_#{phase}_hook".to_sym
          Whiskey::Bootloader.add_boot_hook(phase, hook_name, block, **options)
        end
      end
    end
  end
end
