# Copyright 2026 IBM Corp. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative 'config_fetcher'
require_relative '../logger'

# BackgroundRetryManager
#
# Implements exponential backoff retry strategy for long-term configuration fetch failures.
# This is the "Tier 2" retry mechanism that activates after immediate retries fail.
#
# Key Features:
# - Exponential backoff: Delays increase exponentially (2^attempt)
# - Jitter: Random delays prevent thundering herd
# - Cap: Maximum delay capped at ~1 hour
# - Thread-safe: Uses Mutex for concurrent access
# - Graceful shutdown: Properly cleans up threads
#
# Retry Timeline Example:
#   Attempt 1: ~2.3 minutes
#   Attempt 2: ~4.7 minutes
#   Attempt 3: ~9.1 minutes
#   Attempt 4: ~18.5 minutes
#   Attempt 5: ~37.2 minutes
#   Attempt 6+: ~60 minutes (capped)
#
class BackgroundRetryManager
  
  attr_reader :active, :attempt
  
  # Initialize the retry manager
  #
  # @param collection_id [String] Collection ID for API request
  # @param environment_id [String] Environment ID for API request
  # @param logger [Logger] Optional logger instance (creates new one if not provided)
  def initialize(collection_id:, environment_id:, logger: nil)
    @collection_id = collection_id
    @environment_id = environment_id
    @logger = logger || Logger.instance
    
    # Initialize ConfigFetcher
    @config_fetcher = ConfigFetcher.new(
      collection_id: collection_id,
      environment_id: environment_id,
      logger: @logger
    )
    
    # State management
    @active = false
    @attempt = 0
    @cap_ms = nil
    
    # Thread management
    @retry_thread = nil
    @mutex = Mutex.new
    
    @logger.info("BackgroundRetryManager initialized")
  end
  
  # Start the background retry loop
  #
  # This method:
  # 1. Checks if retry is already active (prevents duplicate retries)
  # 2. Initializes retry state (attempt counter, cap delay)
  # 3. Schedules the first retry attempt
  #
  # @param reason [String] The reason for starting retry (for logging)
  # @return [Boolean] true if started, false if already active
  def start(reason:)
    # Thread-safe check and initialization
    should_start = false
    
    @mutex.synchronize do
      if @active
        @logger.info("⚠️  Background retry already active (attempt ##{@attempt}). Reason: #{reason}")
        return false
      end
      
      # Initialize retry state
      @active = true
      @attempt = 0
      @cap_ms = compute_cap_delay_ms
      should_start = true
    end
    
    if should_start
      cap_hours = (@cap_ms / 3600000.0).round(2)
      @logger.info("🔄 Starting background retry (cap #{cap_hours} hours). Reason: #{reason}")
      schedule_next_attempt(reason)
    end
    
    true
  end
  
  # Stop the background retry loop
  #
  # This method:
  # 1. Sets active flag to false (stops scheduling new attempts)
  # 2. Kills the current retry thread if running
  # 3. Resets all state variables
  #
  # Thread-safe and idempotent (safe to call multiple times)
  def stop
    @mutex.synchronize do
      return unless @active
      
      @active = false
      @attempt = 0
      @cap_ms = nil
    end
    
    # Kill retry thread outside mutex to avoid deadlock
    if @retry_thread && @retry_thread.alive?
      @retry_thread.kill
      @retry_thread = nil
    end
    
    @logger.info("✓ Background retry stopped")
  end
  
  # Check if retry is currently active
  #
  # @return [Boolean] true if retry loop is running
  def active?
    @mutex.synchronize { @active }
  end
  
  # Get current attempt number
  #
  # @return [Integer] Current retry attempt (0-based)
  def current_attempt
    @mutex.synchronize { @attempt }
  end
  
  private
  
  # Schedule the next retry attempt
  #
  # This is the core of the retry mechanism:
  # 1. Calculates delay using exponential backoff (0 for first attempt)
  # 2. Logs the schedule
  # 3. Spawns a thread that:
  #    - Sleeps for the calculated delay (0 for first attempt)
  #    - Executes the retry (calls fetch_from_api)
  #    - Decides next action based on result
  #
  # @param reason [String] Reason for this retry attempt
  def schedule_next_attempt(reason)
    # First attempt (attempt 0) happens immediately, subsequent attempts use exponential backoff
    delay_ms = @attempt == 0 ? 0 : compute_next_delay_ms(@attempt, @cap_ms)
    delay_sec = delay_ms / 1000.0
    delay_min = (delay_ms / 60000.0).round(2)
    
    if @attempt == 0
      @logger.warning("⏰ #{reason} - Starting first retry attempt immediately")
    else
      @logger.warning("⏰ #{reason} - Retry scheduled in #{delay_min} minutes (attempt ##{@attempt + 1})")
    end
    
    # Spawn new thread for this retry attempt
    @retry_thread = Thread.new do
      begin
        # Sleep for the calculated delay
        # First attempt: 0 seconds (immediate)
        # Subsequent attempts: exponential backoff
        sleep(delay_sec)
        
        # Check if still active after sleep (might have been stopped)
        next unless @active
        
        @logger.info("🔄 Executing retry attempt ##{@attempt + 1}")
        
        # Execute the retry by calling ConfigFetcher
        result = @config_fetcher.fetch
        
        # Decision tree based on result
        if result[:ok]
          # ✅ SUCCESS: Configuration fetched successfully
          @logger.info("=" * 80)
          @logger.info("✅ SUCCESS: Configurations fetched successfully!")
          @logger.info("=" * 80)
          @config_fetcher.display_response(result[:data])
          @config_fetcher.process_and_load_configurations(result[:data])
          stop
          next
        end
        
        unless result[:retryable]
          # ❌ NON-RETRYABLE ERROR: Client error (4xx except 429)
          # Stop retrying - user needs to fix the issue
          @logger.error("❌ Non-retryable error (#{result[:status]}) - stopping retry")
          stop
          next
        end
        
        # 🔄 RETRYABLE ERROR: 429 or 5xx
        # Increment attempt counter and schedule next retry
        @mutex.synchronize do
          @attempt += 1
        end
        
        next_reason = "Failed to fetch configurations. Status: #{result[:status]}"
        @logger.warning("⚠️  Retry attempt ##{@attempt} failed - scheduling next attempt")
        
        # Recursive call to schedule next attempt with increased delay
        schedule_next_attempt(next_reason)
        
      rescue StandardError => e
        # Handle any unexpected errors in the retry thread
        @logger.error("❌ Error in retry thread: #{e.message}")
        @logger.error(e.backtrace.join("\n"))
        
        # Try to schedule next attempt if still active
        if @active
          @mutex.synchronize { @attempt += 1 }
          schedule_next_attempt("Exception in retry: #{e.message}")
        end
      end
    end
  end
  
  # Compute base delay with jitter
  #
  # Base delay: 2 minutes (120,000 ms)
  # Jitter: 0-54 seconds (0-54,000 ms)
  # Total: 2.0 - 2.9 minutes
  #
  # Jitter prevents synchronized retries across multiple clients
  # (thundering herd problem)
  #
  # @return [Integer] Base delay in milliseconds
  def compute_base_delay_ms
    base_ms = 2 * 60 * 1000  # 2 minutes = 120,000 ms
    jitter_ms = (0.9 * 60 * 1000 * rand).floor  # 0-54 seconds
    base_ms + jitter_ms
  end
  
  # Compute cap delay with jitter
  #
  # Cap: 1 hour (3,600,000 ms)
  # Jitter: 0-59 seconds (0-59,000 ms)
  # Total: 60:00 - 60:59 minutes
  #
  # This is the maximum delay between retries
  #
  # @return [Integer] Cap delay in milliseconds
  def compute_cap_delay_ms
    base_ms = 60 * 60 * 1000  # 1 hour = 3,600,000 ms
    jitter_seconds = rand(60)  # 0-59 seconds
    base_ms + (jitter_seconds * 1000)
  end
  
  # Compute next delay using exponential backoff
  #
  # Formula: min(base_delay * 2^attempt, cap_delay)
  #
  # Example progression:
  #   Attempt 0: 2.3 min * 2^0 = 2.3 min
  #   Attempt 1: 2.3 min * 2^1 = 4.6 min
  #   Attempt 2: 2.3 min * 2^2 = 9.2 min
  #   Attempt 3: 2.3 min * 2^3 = 18.4 min
  #   Attempt 4: 2.3 min * 2^4 = 36.8 min
  #   Attempt 5: 2.3 min * 2^5 = 73.6 min → capped at 60 min
  #
  # @param attempt [Integer] Current attempt number (0-based)
  # @param cap_ms [Integer] Maximum delay in milliseconds
  # @return [Integer] Calculated delay in milliseconds
  def compute_next_delay_ms(attempt, cap_ms)
    # Calculate exponential delay
    exp_ms = compute_base_delay_ms * (2 ** attempt)
    
    # Cap at maximum delay
    [exp_ms, cap_ms].min
  end
end

