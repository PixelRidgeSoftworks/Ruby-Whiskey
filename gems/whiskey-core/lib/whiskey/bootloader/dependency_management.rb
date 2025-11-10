# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Dependency management functionality for subsystem boot ordering
      module DependencyManagement
        # Get list of registered subsystems ordered by priority and dependencies
        # @return [Array<Array>] array of [name, info] pairs ordered by priority
        def subsystems_by_priority(subsystem_list = nil)
          subsystems = subsystem_list || @subsystem_registry

          # Sort by dependencies first, then by priority
          dependency_sorted = resolve_dependency_order(subsystems.keys)
          dependency_sorted.map { |name| [name, subsystems[name]] }
        end

        private

        # Resolve dependency order for subsystems
        # @param subsystem_names [Array<Symbol>] subsystem names to order
        # @return [Array<Symbol>] dependency-resolved order
        def resolve_dependency_order(subsystem_names)
          resolved = []
          unresolved = subsystem_names.dup

          while unresolved.any?
            before_count = unresolved.size

            unresolved.each do |name|
              info = @subsystem_registry[name]
              dependencies = info ? info[:depends_on] : []

              # Check if all dependencies are already resolved or not in our target list
              next unless dependencies.all? { |dep| resolved.include?(dep) || !subsystem_names.include?(dep) }

              # Verify dependencies are registered
              missing_deps = dependencies.reject { |dep| @subsystem_registry.key?(dep) }
              if missing_deps.any?
                log_warn("⚠️  Subsystem #{name} has missing dependencies: #{missing_deps.join(', ')}")
              end

              resolved << name
              unresolved.delete(name)
            end

            # Check for circular dependencies
            next unless unresolved.size == before_count

            log_warn("⚠️  Circular dependency detected, booting remaining subsystems by priority: #{unresolved.join(', ')}")
            # Sort remaining by priority and add them
            unresolved.sort_by { |name| @subsystem_registry[name][:priority] }.each do |name|
              resolved << name
            end
            break
          end

          resolved
        end
      end
    end
  end
end
