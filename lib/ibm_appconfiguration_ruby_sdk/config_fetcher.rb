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

require_relative "api_manager"
require_relative "url_builder"
require_relative "utils"
require_relative "logger"
require_relative "models/feature"
require_relative "models/property"
require_relative "models/segment"
# ConfigFetcher
#
# Handles fetching configurations from the App Configuration API.
# This class encapsulates all API call logic and response handling.
#
module IbmAppconfigurationRubySdk
  # Handles fetching configurations from the App Configuration API
  class ConfigFetcher
    include IbmAppconfigurationRubySdk::Utils

    # Maps IBM App Configuration error codes to their HTTP equivalents.
    # The IBM Cloud SDK Core gem puts the service's errorCode string in
    # ApiException#code rather than the HTTP status integer.
    IBM_ERROR_CODE_TO_HTTP_STATUS = {
      # 404 — resource not found
      "FTEC1000E" => 404,  # Collection not found
      "FTEC1001E" => 404,  # Environment not found
      "FTEC1002E" => 404,  # Feature not found
      "FTEC1003E" => 404,  # Property not found
      # 401 — authentication
      "BXNIM0415E" => 401, # API key not found
      "BXNIM0106E" => 401, # Token expired
      # 429 — rate limit
      "FTEC4290E" => 429
    }.freeze

    # Initialize the config fetcher
    #
    # @param collection_id [String] Collection ID for API request
    # @param environment_id [String] Environment ID for API request
    # @param handler [ConfigurationHandler] Handler to push loaded configurations into
    # @param logger [Logger] Optional logger instance
    def initialize(collection_id:, environment_id:, handler:, logger: nil)
      @collection_id = collection_id
      @environment_id = environment_id
      @handler = handler
      @logger = logger || Logger.instance
    end

    # Fetch configuration from API
    #
    # Makes a direct API call to the /config endpoint
    # Returns a hash with status information
    #
    # @return [Hash] Result hash with :ok, :retryable, :status, and :data keys
    def fetch
      # Force the IAM token manager to check expiry and refresh before every
      # config GET.  Without this, long-running processes reuse a cached token
      # that the server rejects with 401 once it expires (~1 hour).
      ApiManager.refresh_token!

      # Get the BaseService client
      client = ApiManager.base_service_client
      url_builder = UrlBuilder.instance

      # Build the API endpoint URL
      api_path = "/apprapp/feature/v1/instances/#{url_builder.guid}/config"

      @logger.info("Calling API: #{url_builder.base_service_url}#{api_path}")

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
        @logger.info(Constants::CONFIG_API_CALL_SUCCESS)
        {
          ok: true,
          retryable: false,
          status: 200,
          data: response.result
        }
      else
        # Unexpected status code
        @logger.warning("Unexpected status code: #{response.status}")
        {
          ok: false,
          retryable: true,
          status: response.status,
          data: nil
        }
      end
    rescue IBMCloudSdkCore::ApiException => e
      # e.code is the IBM error-code string (e.g. "FTEC1000E"), not the HTTP status.
      # Map known IBM error codes to HTTP statuses; fall back to parsing as integer.
      http_status = IBM_ERROR_CODE_TO_HTTP_STATUS.fetch(e.code.to_s, e.code.to_i)
      # If still 0, infer from the error message text
      if http_status.zero?
        http_status = case e.error.to_s
                      when /not found/i, /not available/i then 404
                      when /unauthorized/i, /not authorized/i then 401
                      when /forbidden/i                    then 403
                      when /too many requests/i            then 429
                      else 500
                      end
      end

      IbmAppconfigurationRubySdk::APIError.from_status(http_status, message: e.message)
      @logger.error("API Exception (Status: #{http_status})")

      retryable = http_status == 429 || http_status >= 500

      {
        ok: false,
        retryable: retryable,
        status: http_status,
        data: nil
      }
    rescue StandardError => e
      @logger.error("Unexpected error: #{e.class.name} - #{e.message}")

      # Treat unexpected errors as retryable
      {
        ok: false,
        retryable: true,
        status: 500,
        data: nil
      }
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
        @logger.info(Constants::CONFIG_PROCESSING_RESPONSE)

        # The IBM SDK normally returns a parsed Hash, but on some retry paths
        # it may return a raw JSON String — parse it if so.
        parsed_response = api_response.is_a?(String) ? JSON.parse(api_response) : api_response

        # Convert string keys to symbol keys if needed
        symbolized_data = symbolize_keys(parsed_response)

        # Extract configurations using utils.rb method
        # This validates the data and extracts only the relevant features, properties, and segments
        # for the specified environment and collection
        extracted_config = extract_configurations(
          symbolized_data,
          @environment_id,
          @collection_id
        )

        @logger.info(Constants::CONFIG_EXTRACTED_SUCCESSFULLY)

        # Load the extracted configurations to cache
        success = load_configurations_to_cache(extracted_config)

        if success
          @logger.info(Constants::CONFIG_PROCESSED_AND_LOADED)
        else
          @logger.error(Constants::CONFIG_LOAD_FAILED)
        end

        success
      rescue StandardError => e
        @logger.error("Error processing API response: #{e.class.name} - #{e.message}")
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
        @logger.info(Constants::CONFIG_LOADING_TO_CACHE)

        # Delegate to the injected handler (single source of truth)
        @handler.load_configurations_to_cache(data)

        @logger.info(Constants::CONFIG_LOADED_TO_CACHE)

        true
      rescue StandardError => e
        @logger.error("Error loading configurations to cache: #{e.class.name} - #{e.message}")
        false
      end
    end
  end
end
