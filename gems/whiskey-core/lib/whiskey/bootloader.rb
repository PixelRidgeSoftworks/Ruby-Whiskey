# frozen_string_literal: true

# API Change: Whiskey.bootloader now returns singleton instance for consistent delegation to instance state

##
# Ruby Whiskey Framework Bootloader
#
# The Bootloader is the central orchestration system for the Ruby Whiskey framework,
# designed with a "no magic, full control" philosophy. This modular version splits
# functionality across dedicated files for better maintainability while preserving
# the same public API.
#
# * Subsystem Registration: Register and manage framework components (ORM, Web, CLI, etc.)
# * Dependency Management: Handle subsystem dependencies and boot ordering
# * Configuration Integration: Unified configuration loading and caching
# * Lifecycle Management: Boot hooks and graceful shutdown procedures
# * Error Recovery: Robust error handling and subsystem recovery mechanisms
#
# Key Features:
# * Modular logger adapter system for flexible logging backends
# * Environment validation and awareness
# * Diagnostic introspection capabilities
# * Thread-safe operations with parallel boot support
# * No external dependencies beyond Ruby standard library
#
# Entry Points:
# * Whiskey.boot! - Initialize the framework
# * Whiskey.shutdown! - Graceful shutdown
# * Whiskey.register_subsystem - Add new subsystems
# * Whiskey.status_summary - Quick diagnostic overview
# * Whiskey.config - Access configuration cache
#
# Example Usage:
#   Whiskey.boot!                                    # Boot with default profile
#   Whiskey.register_subsystem(:orm, ORM, priority: 10)  # Register subsystem
#   puts Whiskey.status_summary                      # Get diagnostic info
#
#   # Environment validation examples
#   Whiskey.env!                                     # Validates current environment
#   # => raises Core::InvalidEnvironmentError if env not in Core::ENVIRONMENTS
#
#   # Framework state validation examples
#   Whiskey.ensure_booted!                           # Ensures framework is booted
#   # => raises boot_error, "Framework not booted" unless booted?
#
#   # Status summary with compact mode examples
#   Whiskey.status_summary                           # Full status with all fields
#   Whiskey.status_summary(compact: true)            # Compact mode (omits subsystem details)
#
# @author PixelRidge Softworks
# @version 2.0.0
# @since 1.0.0

# Load core modular components
require_relative 'log'
require_relative 'environment'
require_relative 'delegators'

# Load all bootloader modules
require_relative 'bootloader/structs'
require_relative 'bootloader/config_cache'
require_relative 'bootloader/lifecycle_events'
require_relative 'bootloader/analytics'
require_relative 'bootloader/dependency_management'
require_relative 'bootloader/shutdown'
require_relative 'bootloader/error_recovery'
require_relative 'bootloader/boot_profiles'
require_relative 'bootloader/core'
