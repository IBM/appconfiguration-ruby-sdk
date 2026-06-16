#!/usr/bin/env ruby
# frozen_string_literal: true

require "securerandom"
require_relative "../lib/ibm_appconfiguration_ruby_sdk/app_configuration"

# Configuration
REGION = ""
GUID = ""
APIKEY = ""
COLLECTION_ID = ""
ENVIRONMENT_ID = ""

def initialize_app_config
  # Get AppConfiguration singleton instance
  client = IbmAppconfigurationRubySdk::AppConfiguration.instance

  # Initialize the SDK
  client.init(REGION, GUID, APIKEY)

  # Set context with options (only pass options that have values)
  client.set_context(
    COLLECTION_ID,
    ENVIRONMENT_ID,
    {
      live_config_update_enabled: true
    }
  )

  # Wait for initial configuration fetch
  sleep 3

  client
end

def main
  puts "Initializing App Configuration SDK..."
  client = initialize_app_config
  puts "✅ SDK initialized successfully"
  puts ""

  disabled_evals = 0
  enabled_evals = 0

  loop do
    # Generate random user ID (10 character hex string)
    user_id = SecureRandom.hex(5).upcase

    entity_id = user_id
    entity_attributes = {
      email: "#{user_id}@ibm.com" # Must match segment attribute_name: "ibmemail"
    }

    # Get feature using the AppConfiguration client
    feature = client.get_feature("demoflg")

    if feature.nil?
      puts "\n❌ Feature 'demoflg' not found"
      sleep 1
      next
    end

    # Get current value
    begin
      feature_value = feature.get_current_value(entity_id, entity_attributes)

      if feature_value && feature_value[:value]
        enabled_evals += 1
        # Uncomment to simulate failures
        # if rand >= 0.4
        #   enabled_fails += 1
        #   raise StandardError, 'We failed!'
        # end
      else
        disabled_evals += 1
        # Uncomment to simulate failures
        # if rand >= 0.99
        #   disabled_fails += 1
        #   raise StandardError, 'We failed!'
        # end
      end
    rescue StandardError
      # Handle exceptions
      # puts "Exception: #{e.message}"
    end

    # Print stats (with carriage return to overwrite line)
    # print "enabled_evals #{enabled_evals}, enabled_fails #{enabled_fails}, disabled_evals #{disabled_evals}, disabled_fails #{disabled_fails}\r"
    print "enabled_evals #{enabled_evals}, disabled_evals #{disabled_evals}\r"
    $stdout.flush

    # Small delay between evaluations (10ms)
    sleep 0.01
  end
end

# Handle Ctrl+C gracefully
trap("INT") do
  puts "\n\n🛑 Shutting down..."
  exit(0)
end

# Run main
main
