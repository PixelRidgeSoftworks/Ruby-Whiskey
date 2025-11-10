# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Structured error for boot-related failures
      BootError = Struct.new(:subsystem, :phase, :message, :timestamp, :backtrace) do
        def to_h
          {
            subsystem: subsystem,
            phase: phase,
            message: message,
            timestamp: timestamp,
            backtrace: backtrace
          }
        end
      end

      # Context passed to boot hooks during execution
      BootContext = Struct.new(:name, :config, :logger, :env, :started_at, :ended_at) do
        def duration
          return nil unless started_at && ended_at

          ended_at - started_at
        end
      end
    end
  end
end
