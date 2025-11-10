# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Analytics functionality for boot process monitoring
      module Analytics
        # Get comprehensive boot analytics
        # @return [Hash] structured analytics data
        def analytics
          return {} unless @boot_sequence_completed && @boot_phases.any?

          durations = @boot_phases.values.map { |phase| phase[:duration] || 0 }

          {
            overview: {
              total_boot_time: @boot_duration,
              subsystem_count: @subsystem_manifest.size,
              failed_count: @failed_subsystems.size,
              error_count: @boot_errors.size,
              average_subsystem_boot_time: durations.any? ? durations.sum / durations.size : 0,
              parallel_boot_used: @boot_phases.values.any? { |p| p[:parallel] }
            },
            timing: {
              fastest_subsystem: find_fastest_subsystem,
              slowest_subsystem: find_slowest_subsystem,
              boot_order: @boot_phases.keys,
              phase_durations: @boot_phases.transform_values { |phase| phase[:duration] }
            },
            dependencies: analyze_dependency_chain,
            errors: @boot_errors.map(&:to_h),
            manifest: @subsystem_manifest
          }
        end

        private

        # Find fastest booting subsystem for analytics
        # @return [Hash, nil] fastest subsystem info
        def find_fastest_subsystem
          return nil if @boot_phases.empty?

          fastest = @boot_phases.min_by { |_name, phase| phase[:duration] || Float::INFINITY }
          fastest ? { name: fastest[0], duration: fastest[1][:duration] } : nil
        end

        # Find slowest booting subsystem for analytics
        # @return [Hash, nil] slowest subsystem info
        def find_slowest_subsystem
          return nil if @boot_phases.empty?

          slowest = @boot_phases.max_by { |_name, phase| phase[:duration] || 0 }
          slowest ? { name: slowest[0], duration: slowest[1][:duration] } : nil
        end

        # Analyze dependency chain for analytics
        # @return [Hash] dependency analysis
        def analyze_dependency_chain
          dependency_map = {}
          circular_deps = []

          @subsystem_registry.each do |name, info|
            deps = info[:depends_on] || []
            dependency_map[name] = {
              depends_on: deps,
              dependency_depth: calculate_dependency_depth(name, deps),
              missing_dependencies: deps.reject { |dep| @subsystem_registry.key?(dep) }
            }
          end

          {
            dependency_map: dependency_map,
            max_depth: dependency_map.values.map { |v| v[:dependency_depth] }.max || 0,
            circular_dependencies: circular_deps
          }
        end

        # Calculate dependency depth for a subsystem
        # @param name [Symbol] subsystem name
        # @param deps [Array<Symbol>] direct dependencies
        # @param visited [Array<Symbol>] visited subsystems (for cycle detection)
        # @return [Integer] dependency depth
        def calculate_dependency_depth(name, deps, visited = [])
          return 0 if deps.empty?
          return 0 if visited.include?(name) # Circular dependency

          visited += [name]
          max_depth = 0

          deps.each do |dep|
            dep_info = @subsystem_registry[dep]
            next unless dep_info

            dep_deps = dep_info[:depends_on] || []
            depth = 1 + calculate_dependency_depth(dep, dep_deps, visited)
            max_depth = [max_depth, depth].max
          end

          max_depth
        end
      end
    end
  end
end
