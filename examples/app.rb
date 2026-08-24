#!/usr/bin/env ruby
# frozen_string_literal: true

# ---------------------------------------------------------------------------
# IBM App Configuration Ruby SDK — example application
#
# Fill in your credentials in Section 1 below, then run:
#   ruby appconfiguration-ruby-sdk/examples/app.rb
# ---------------------------------------------------------------------------

require "securerandom"
require_relative "../lib/ibm_appconfiguration_ruby_sdk"

# ---------------------------------------------------------------------------
# 1. Credentials — fill these in
# ---------------------------------------------------------------------------
REGION         = 
GUID           = 
APIKEY         =  
COLLECTION_ID  = 
ENVIRONMENT_ID = 

# ---------------------------------------------------------------------------
# 2. SDK-wide options via the block-configure pattern
# ---------------------------------------------------------------------------
IbmAppconfigurationRubySdk::AppConfiguration.configure do |config|
  config.debug                = false   # set true for verbose SDK logging
  config.use_private_endpoint = false   # set true to use IBM private network
end

# ---------------------------------------------------------------------------
# 3. Initialise the SDK
# ---------------------------------------------------------------------------
def initialize_app_config
  client = IbmAppconfigurationRubySdk::AppConfiguration.instance

  client.init(region: REGION, guid: GUID, apikey: APIKEY)

  # Fires on the first configuration fetch and every subsequent live update.
  client.register_configuration_update_listener do
    puts "\n[listener] Configurations refreshed."
  end

  client.set_context(
    COLLECTION_ID,
    ENVIRONMENT_ID,
    live_config_update_enabled: true
  )

  sleep 3 # allow initial fetch + WebSocket handshake to settle

  client

rescue IbmAppconfigurationRubySdk::AuthenticationError => e
  warn "\n[fatal] Authentication failed (HTTP #{e.http_status}): #{e.message}"
  warn "        Check that APIKEY is a valid, non-expired service credential."
  exit 1
rescue IbmAppconfigurationRubySdk::APIError => e
  warn "\n[fatal] API error (HTTP #{e.http_status}): #{e.message}"
  exit 1
rescue IbmAppconfigurationRubySdk::ConfigurationError => e
  warn "\n[fatal] SDK configuration error: #{e.message}"
  exit 1
rescue StandardError => e
  warn "\n[fatal] Unexpected error: #{e.class}: #{e.message}"
  exit 1
end

# ---------------------------------------------------------------------------
# 4. Evaluation loop
# ---------------------------------------------------------------------------
def run_evaluation_loop(client)
  enabled_evals  = 0
  disabled_evals = 0

  loop do
    user_id           = SecureRandom.hex(5).upcase
    entity_id         = user_id
    entity_attributes = { email: "#{user_id}@ibm.com" }

    feature = client.get_feature("demoflg")

    if feature.nil?
      warn "\n[warn] Feature 'demoflg' not found — check COLLECTION_ID / ENVIRONMENT_ID."
      sleep 1
      next
    end

    begin
      # get_current_value returns an EvaluationResult struct.
      # result.value is the resolved flag value — truthy means enabled.
      result = feature.get_current_value(entity_id, entity_attributes)

      if result&.value
        enabled_evals += 1
      else
        disabled_evals += 1
      end
    rescue StandardError
      # swallow exceptions to keep the loop running
    end

    print "enabled_evals #{enabled_evals}, disabled_evals #{disabled_evals}\r"
    $stdout.flush
    sleep 0.01
  end
end

# ---------------------------------------------------------------------------
# 5. Entry point
# ---------------------------------------------------------------------------
trap("INT") do
  puts "\n\nShutting down — goodbye."
  exit 0
end

puts "Initialising IBM App Configuration Ruby SDK…"
client = initialize_app_config
puts "SDK initialised. Starting evaluation loop (Ctrl-C to stop).\n\n"
run_evaluation_loop(client)
