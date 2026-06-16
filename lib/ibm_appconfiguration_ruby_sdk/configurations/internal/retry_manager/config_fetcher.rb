# frozen_string_literal: true

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

require_relative "../../../core/api_manager"
require_relative "../../../core/url_builder"
require_relative "../utils"
require_relative "../logger"
require_relative "../../models/feature"
require_relative "../../models/property"
require_relative "../../models/segment"
require_relative "../../configuration_handler"

# ConfigFetcher
#
# Handles fetching configurations from the App Configuration API.
# This class encapsulates all API call logic and response handling.
#
class ConfigFetcher
  # Initialize the config fetcher
  #
  # @param collection_id [String] Collection ID for API request
  # @param environment_id [String] Environment ID for API request
  # @param logger [Logger] Optional logger instance
  def initialize(collection_id:, environment_id:, logger: nil)
    @collection_id = collection_id
    @environment_id = environment_id
    @logger = logger || Logger.instance
  end

  # Fetch configuration from API
  #
  # Makes a direct API call to the /config endpoint
  # Returns a hash with status information
  #
  # @return [Hash] Result hash with :ok, :retryable, :status, and :data keys
  def fetch
    # Get the BaseService client
    client = ApiManager.base_service_client
    url_builder = UrlBuilder.instance

    # Build the API endpoint URL
    api_path = "/apprapp/feature/v1/instances/#{url_builder.guid}/config"

    @logger.info("📡 Calling API: #{url_builder.base_service_url}#{api_path}")

    # Make the API request
    response = client.request(
      method: "GET",
      url: api_path,
      headers: ApiManager.headers,
      params: {
        action: "sdkConfig",
        collection_id: @collection_id,
        environment_id: @environment_id
      }
    )

    # Success case
    if response.status == 200
      @logger.info("✓ API call successful (200)")
      {
        ok: true,
        retryable: false,
        status: 200,
        data: response.result
      }
    else
      # Unexpected status code
      @logger.warn("⚠️  Unexpected status code: #{response.status}")
      {
        ok: false,
        retryable: true,
        status: response.status,
        data: nil
      }
    end
  rescue IBMCloudSdkCore::ApiException => e
    status_code = e.code.to_i
    @logger.error("❌ API Exception: #{e.message} (Status: #{status_code})")

    # Determine if error is retryable
    # Non-retryable: 4xx except 429
    # Retryable: 429, 5xx
    retryable = status_code == 429 || status_code >= 500

    {
      ok: false,
      retryable: retryable,
      status: status_code,
      data: nil
    }
  rescue StandardError => e
    @logger.error("❌ Unexpected error: #{e.message}")
    @logger.error(e.backtrace.first(3).join("\n"))

    # Treat unexpected errors as retryable
    {
      ok: false,
      retryable: true,
      status: 500,
      data: nil
    }
  end

  # Display API response in a readable format
  #
  # @param data [Hash] API response data
  def display_response(data)
    # require 'json'

    # @logger.info("\n📊 API Response Summary:")
    # @logger.info("-" * 80)

    # # Display features
    # if data['features'] && data['features'].any?
    #   @logger.info("\n📋 Features (#{data['features'].length}):")
    #   data['features'].each_with_index do |feature, index|
    #     @logger.info("  #{index + 1}. #{feature['name']} (#{feature['feature_id']})")
    #     @logger.info("     Type: #{feature['type']}")
    #     @logger.info("     Enabled: #{feature['enabled']}")
    #     if feature['segment_rules'] && feature['segment_rules'].any?
    #       @logger.info("     Segment Rules: #{feature['segment_rules'].length}")
    #     end
    #   end
    # else
    #   @logger.info("\n📋 Features: None")
    # end

    # # Display properties
    # if data['properties'] && data['properties'].any?
    #   @logger.info("\n🔧 Properties (#{data['properties'].length}):")
    #   data['properties'].each_with_index do |property, index|
    #     @logger.info("  #{index + 1}. #{property['name']} (#{property['property_id']})")
    #     @logger.info("     Type: #{property['type']}")
    #     @logger.info("     Value: #{property['value']}")
    #     if property['segment_rules'] && property['segment_rules'].any?
    #       @logger.info("     Segment Rules: #{property['segment_rules'].length}")
    #     end
    #   end
    # else
    #   @logger.info("\n🔧 Properties: None")
    # end

    # # Display segments
    # if data['segments'] && data['segments'].any?
    #   @logger.info("\n👥 Segments (#{data['segments'].length}):")
    #   data['segments'].each_with_index do |segment, index|
    #     @logger.info("  #{index + 1}. #{segment['name']} (#{segment['segment_id']})")
    #     if segment['rules'] && segment['rules'].any?
    #       @logger.info("     Rules: #{segment['rules'].length}")
    #     end
    #   end
    # else
    #   @logger.info("\n👥 Segments: None")
    # end

    # @logger.info("\n📄 Full JSON Response:")
    # @logger.info("-" * 80)
    # @logger.info(JSON.pretty_generate(data))
    # @logger.info("=" * 80)
  end

  # Process API response and load to cache
  #
  # This method:
  # 1. Takes the raw API response
  # 2. Calls extract_configurations to parse and validate the data
  # 3. Calls load_configurations_to_cache to store in cache
  #
  # @param api_response [Hash] Raw API response data
  # @return [Boolean] true if processing was successful, false otherwise
  def process_and_load_configurations(api_response)
    return false unless api_response

    begin
      @logger.info("🔄 Processing API response...")

      # Convert string keys to symbol keys if needed
      symbolized_data = symbolize_keys(api_response)

      # Extract configurations using utils.rb method
      # This validates the data and extracts only the relevant features, properties, and segments
      # for the specified environment and collection
      extracted_config = extract_configurations(
        symbolized_data,
        @environment_id,
        @collection_id
      )

      @logger.info("✓ Configurations extracted successfully")
      @logger.info("  Features: #{extracted_config[:features]&.length || 0}")
      @logger.info("  Properties: #{extracted_config[:properties]&.length || 0}")
      @logger.info("  Segments: #{extracted_config[:segments]&.length || 0}")

      # Load the extracted configurations to cache
      success = load_configurations_to_cache(extracted_config)

      if success
        @logger.info("✅ Configurations processed and loaded successfully")
      else
        @logger.error("❌ Failed to load configurations to cache")
      end

      success
    rescue StandardError => e
      @logger.error("❌ Error processing API response: #{e.message}")
      @logger.error(e.backtrace.first(5).join("\n"))
      false
    end
  end

  # Load configurations to cache
  #
  # Delegates to ConfigurationHandler singleton to maintain a single source of truth.
  # This ensures all parts of the application use the same cache.
  #
  # @param data [Hash] Configuration data with :features, :properties, and :segments keys
  # @return [Boolean] true if configurations were loaded successfully
  def load_configurations_to_cache(data)
    return false unless data

    begin
      @logger.info("📦 Loading configurations to ConfigurationHandler cache...")

      # Delegate to ConfigurationHandler singleton (single source of truth)
      handler = ConfigurationHandler.instance
      handler.load_configurations_to_cache(data)

      @logger.info("✅ Configurations loaded to cache successfully")
      @logger.info("  ✓ Features: #{data[:features]&.length || 0}")
      @logger.info("  ✓ Properties: #{data[:properties]&.length || 0}")
      @logger.info("  ✓ Segments: #{data[:segments]&.length || 0}")

      true
    rescue StandardError => e
      @logger.error("❌ Error loading configurations to cache: #{e.message}")
      @logger.error(e.backtrace.first(5).join("\n"))
      false
    end
  end
end
