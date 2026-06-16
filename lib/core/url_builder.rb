# Copyright 2026 IBM Corp. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# frozen_string_literal: true

require 'singleton'



##
# This module provides methods to construct headers & different URLs used by the SDK.
#
# The UrlBuilder class implements a Singleton pattern to ensure consistent URL
# configuration across the SDK. It handles:
# - HTTP/HTTPS endpoints for App Configuration service
# - WebSocket (WSS) connections for real-time updates
# - IAM authentication URLs
# - Support for both public and private endpoints
# - Environment-specific URL overrides for dev/staging/testing
#
##
class UrlBuilder
  include Singleton

  # Constants for URL construction
  HTTPS_PROTOCOL = 'https://'
  WEBSOCKET_PROTOCOL = 'wss://'
  BASE_URL = '.apprapp.cloud.ibm.com'
  WEBSOCKET_PATH = '/wsfeature'
  SERVICE_PATH = '/apprapp'
  PRIVATE_ENDPOINT_PREFIX = 'private.'

  # IAM URLs
  IAM_TEST_URL = 'iam.test.cloud.ibm.com/identity/token'
  IAM_PROD_URL = 'iam.cloud.ibm.com/identity/token'

  ##
  # Initialize the UrlBuilder with default values
  def initialize
    @region = ''
    @instance_guid = nil
    @apikey = nil
    @override_service_url = nil
    @use_private_endpoint = false
    @websocket_full_url = nil
  end

  ##
  # Set the region value
  #
  # @param value [String] Region name (e.g., 'us-south', 'eu-gb', 'au-syd')
  # @return [String] the region value
  def region=(value)
    @region = value
  end

  ##
  # Get the region value
  #
  # @return [String] the region value
  def region
    @region
  end

  ##
  # Set the service instance GUID
  #
  # @param value [String] GUID of the service instance
  # @return [String] the GUID value
  def guid=(value)
    @instance_guid = value
  end

  ##
  # Get the service instance GUID
  #
  # @return [String] the GUID value
  def guid
    @instance_guid
  end

  ##
  # Set the API key
  #
  # @param value [String] API key of the service instance
  # @return [String] the API key value
  def apikey=(value)
    @apikey = value
  end

  ##
  # Get the API key
  #
  # @return [String] the API key value
  def apikey
    @apikey
  end

  ##
  # Set the overridden base service URL.
  # Used for testing, development, or staging environments.
  #
  # @param value [String] The base service URL
  # @return [String] the override URL value
  def base_service_url=(value)
    @override_service_url = value
  end

  ##
  # Alias for base_service_url= to match AppConfiguration usage
  def set_base_service_url(value)
    self.base_service_url = value
  end

  ##
  # Get the base URL for the App Configuration service instance.
  # Returns the appropriate URL based on environment and endpoint type.
  #
  # @return [String] The base service URL
  #
  # @example Production public endpoint
  #   # Returns: https://us-south.apprapp.cloud.ibm.com
  #   builder.base_service_url
  #
  # @example Production private endpoint
  #   # Returns: https://private.us-south.apprapp.cloud.ibm.com
  #   builder.use_private_endpoint = true
  #   builder.base_service_url
  #
  def base_service_url
    # For dev & stage environments
    if @override_service_url
      return add_private_prefix_to_url(@override_service_url) if @use_private_endpoint

      return @override_service_url
    end

    # For production
    if @use_private_endpoint
      return "#{HTTPS_PROTOCOL}#{PRIVATE_ENDPOINT_PREFIX}#{@region}#{BASE_URL}"
    end

    "#{HTTPS_PROTOCOL}#{@region}#{BASE_URL}"
  end

  ##
  # Get the IAM (Identity and Access Management) URL for authentication.
  #
  # @return [String] The IAM URL
  #
  # @example Production IAM URL
  #   # Returns: https://iam.cloud.ibm.com
  #   builder.iam_url
  #
  # @example Test environment IAM URL
  #   # Returns: https://iam.test.cloud.ibm.com
  #   builder.base_service_url = 'https://test.example.com'
  #   builder.iam_url
  #
  def iam_url
    # For dev & stage environments
    if @override_service_url
      return "#{HTTPS_PROTOCOL}#{PRIVATE_ENDPOINT_PREFIX}#{IAM_TEST_URL}" if @use_private_endpoint

      return "#{HTTPS_PROTOCOL}#{IAM_TEST_URL}"
    end

    # For production
    if @use_private_endpoint
      return "#{HTTPS_PROTOCOL}#{PRIVATE_ENDPOINT_PREFIX}#{IAM_PROD_URL}"
    end

    "#{HTTPS_PROTOCOL}#{IAM_PROD_URL}"
  end

  ##
  # Set the WebSocket URL with collection and environment IDs.
  # Constructs the complete WebSocket URL with query parameters.
  #
  # @param collection_id [String] The collection ID
  # @param environment_id [String] The environment ID
  # @return [String] The constructed WebSocket URL
  #
  # @example
  #   builder.set_websocket_url('collection-1', 'env-prod')
  #   # Sets: wss://us-south.apprapp.cloud.ibm.com/apprapp/wsfeature?instance_id=...&collection_id=collection-1&environment_id=env-prod
  #
  def set_websocket_url(collection_id, environment_id)
    ws = WEBSOCKET_PROTOCOL.dup

    if @override_service_url
      # For dev & stage environments
      temp = @override_service_url.gsub(%r{https?://}, '')
      ws += PRIVATE_ENDPOINT_PREFIX if @use_private_endpoint
      ws += temp
    else
      # For production
      ws += PRIVATE_ENDPOINT_PREFIX if @use_private_endpoint
      ws += @region
      ws += BASE_URL
    end

    @websocket_full_url = "#{ws}#{SERVICE_PATH}#{WEBSOCKET_PATH}?" \
                         "instance_id=#{@instance_guid}&" \
                         "collection_id=#{collection_id}&" \
                         "environment_id=#{environment_id}"
  end

  ##
  # Get the WebSocket URL.
  # Must call set_websocket_url first to construct the URL.
  #
  # @return [String, nil] The WebSocket URL or nil if not set
  def websocket_url
    @websocket_full_url
  end

  ##
  # Enable or disable private endpoint usage.
  # When enabled, all URLs will use IBM Cloud private network routing.
  #
  # @param value [Boolean] Set to true to use private endpoints
  # @return [Boolean] the private endpoint setting
  #
  # @example Enable private endpoint
  #   builder.use_private_endpoint = true
  #   # All URLs will now include 'private.' prefix
  #
  def use_private_endpoint=(value)
    @use_private_endpoint = value
  end

  ##
  # Check if private endpoint is enabled
  #
  # @return [Boolean] true if private endpoint is enabled
  def use_private_endpoint?
    @use_private_endpoint
  end

  private

  ##
  # Add private endpoint prefix to a URL
  #
  # @param url [String] The URL to modify
  # @return [String] The URL with private prefix added
  #
  # @example
  #   add_private_prefix_to_url('https://example.com')
  #   # Returns: https://private.example.com
  #
  def add_private_prefix_to_url(url)
    parts = url.split('://')
    return url if parts.length != 2

    "#{parts[0]}://#{PRIVATE_ENDPOINT_PREFIX}#{parts[1]}"
  end
end
