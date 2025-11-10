# frozen_string_literal: true

module Whiskey
  module Core
    module Bootloader
      # Stress testing module for thread safety regression harness
      # Provides concurrent testing capabilities to verify bootloader stability
      module StressTesting
        # Thread safety stress testing with configurable load
        # Repeatedly calls boot!/shutdown! from multiple threads to verify stability
        # @param thread_count [Integer] number of concurrent threads (default: 4)
        # @param iterations [Integer] number of boot/shutdown cycles per thread (default: 5)
        # @return [Hash] stress test results including timing and error data
        def stress_test_bootloader!(thread_count: 4, iterations: 5)
          return { error: 'Stress testing disabled in production' } if Whiskey.production?

          test_start = Time.now
          results = {
            test_timestamp: test_start,
            thread_count: thread_count,
            iterations: iterations,
            total_cycles: thread_count * iterations,
            successful_cycles: 0,
            failed_cycles: 0,
            deadlocks_detected: 0,
            timing_data: [],
            errors: []
          }

          # Store original state for restoration
          original_booted = @boot_sequence_completed

          begin
            # Create barrier for synchronized start
            barrier = Mutex.new
            threads_ready = 0

            # Launch test threads
            threads = Array.new(thread_count) do |thread_id|
              Thread.new do
                barrier.synchronize { threads_ready += 1 }

                # Wait for all threads to be ready
                Thread.pass until threads_ready == thread_count

                iterations.times do |iteration|
                  cycle_start = Time.now

                  begin
                    # Perform boot/shutdown cycle with timeout protection
                    timeout_result = nil
                    timeout_thread = Thread.new do
                      sleep 10 # 10 second timeout per operation
                      timeout_result = :timeout
                    end

                    boot_result = boot!(dry_run: true, force_reload: true)
                    shutdown_result = graceful_shutdown!

                    timeout_thread.kill

                    if timeout_result == :timeout
                      results[:deadlocks_detected] += 1
                      results[:errors] << {
                        thread_id: thread_id,
                        iteration: iteration,
                        error: 'Operation timeout (possible deadlock)',
                        timestamp: Time.now
                      }
                    elsif boot_result && shutdown_result
                      cycle_time = Time.now - cycle_start
                      results[:successful_cycles] += 1
                      results[:timing_data] << {
                        thread_id: thread_id,
                        iteration: iteration,
                        duration: cycle_time
                      }
                    else
                      results[:failed_cycles] += 1
                      results[:errors] << {
                        thread_id: thread_id,
                        iteration: iteration,
                        error: 'Boot or shutdown failed',
                        timestamp: Time.now
                      }
                    end
                  rescue StandardError => e
                    results[:failed_cycles] += 1
                    results[:errors] << {
                      thread_id: thread_id,
                      iteration: iteration,
                      error: e.message,
                      backtrace: e.backtrace.first(5),
                      timestamp: Time.now
                    }
                  end

                  # Brief pause between iterations
                  sleep 0.1
                end
              end
            end

            # Wait for all threads to complete
            threads.each(&:join)
          rescue StandardError => e
            results[:test_error] = e.message
            results[:test_backtrace] = e.backtrace
          ensure
            # Restore original boot state
            boot!(force_reload: true) if original_booted && !@boot_sequence_completed
          end

          results[:test_duration] = Time.now - test_start
          results[:success_rate] = results[:successful_cycles].to_f / results[:total_cycles] * 100

          # Cache results for diagnostics
          @stress_test_log << results
          @stress_test_log = @stress_test_log.last(10) # Keep only last 10 test runs

          results
        end
      end
    end
  end
end
