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

require "ibm_cloud_sdk_core"
require "uri"
require_relative "url_builder"
require_relative "../configurations/internal/constants"
require_relative "../version"

##
# This module provides the methods to facilitate the API requests to the App Configuration service.
#
# The ApiManager class handles:
# - IAM authentication using IBM Cloud SDK Core
# - HTTP request headers construction
# - BaseService client management with retry logic
# - Bearer token retrieval for WebSocket connections
#
# @example Basic usage
#   ApiManager.set_authenticator
#   client = ApiManager.base_service_client
#   token = ApiManager.token
#
##
# ApiManager facilitates API requests to IBM App Configuration service.
# Manages authentication, HTTP clients, and request headers.
#
class ApiManager
  # SDK version for User-Agent header
  SDK_VERSION = IbmAppconfigurationRubySdk::VERSION

  # Class variables to store singleton instances
  @iam_authenticator = nil
  @base_service_client = nil
  @url_builder = nil

  class << self
    ##
    # Get the request headers for API calls
    #
    # @param is_post [Boolean] Whether this is a POST request (adds Content-Type header)
    # @return [Hash] Hash containing required headers
    #
    # @example GET request headers
    #   headers = ApiManager.headers
    #   # => { 'Accept' => 'application/json', 'User-Agent' => 'appconfiguration-ruby-sdk/0.1.0' }
    #
    # @example POST request headers
    #   headers = ApiManager.headers(true)
    #   # => { 'Accept' => 'application/json', 'User-Agent' => '...', 'Content-Type' => 'application/json' }
    #
    def headers(is_post = false)
      headers = {
        "Accept" => "application/json",
        "User-Agent" => "appconfiguration-ruby-sdk/#{SDK_VERSION}"
      }
      headers["Content-Type"] = "application/json" if is_post
      headers
    end

    ##
    # Sets the IAM Authenticator using the API key from UrlBuilder
    #
    # This method initializes the IBM Cloud IAM authenticator with the
    # API key and IAM URL configured in the UrlBuilder singleton.
    #
    # @return [void]
    # @raise [StandardError] If UrlBuilder is not properly configured
    #
    # @example
    #   url_builder = UrlBuilder.instance
    #   url_builder.apikey = 'your-api-key'
    #   url_builder.region = 'us-south'
    #   ApiManager.set_authenticator
    #
    def set_authenticator
      @url_builder = UrlBuilder.instance

      # Create authenticator with apikey and optional URL
      authenticator_options = {
        apikey: @url_builder.apikey
      }

      # Add URL if it's not the default production URL
      # Check for test/staging environment (iam.test.cloud.ibm.com) or custom URLs
      iam_url = @url_builder.iam_url
      default_prod_url = "#{UrlBuilder::HTTPS_PROTOCOL}#{UrlBuilder::IAM_PROD_URL}"

      if iam_url && iam_url != default_prod_url
        authenticator_options[:url] = iam_url
        puts "🔧 Using custom IAM URL: #{iam_url}"
      else
        puts "🔧 Using default IAM URL: #{default_prod_url}"
      end

      @iam_authenticator = IBMCloudSdkCore::IamAuthenticator.new(authenticator_options)
    end

    ##
    # Get the BaseService client with retry configuration
    #
    # Creates a new BaseService client if one doesn't exist, configured with:
    # - The IAM authenticator
    # - Retry logic (max 3 retries with exponential backoff)
    # - Base service URL from UrlBuilder
    #
    # @return [IBMCloudSdkCore::BaseService] The configured BaseService client
    # @raise [StandardError] If authenticator is not set
    #
    # @example
    #   client = ApiManager.base_service_client
    #   response = client.request(
    #     method: 'GET',
    #     url: '/apprapp/feature/v1/instances/guid/config',
    #     headers: ApiManager.headers
    #   )
    #
    def base_service_client
      if @base_service_client.nil?
        raise "Authenticator not set. Call set_authenticator first." if @iam_authenticator.nil?

        @url_builder ||= UrlBuilder.instance

        @base_service_client = IBMCloudSdkCore::BaseService.new(
          service_name: "app_configuration",
          authenticator: @iam_authenticator,
          service_url: @url_builder.base_service_url
        )

        # Configure retry settings
        # Note: Ruby SDK Core v1.3.0 uses configure_http_client for retry settings
        @base_service_client.configure_http_client(
          timeout: { connect: 60, read: 60, write: 60 }
        )
      end

      @base_service_client
    end

    ##
    # Get the IAM bearer token for WebSocket authentication
    #
    # This method authenticates with IAM and retrieves the bearer token
    # that can be used for WebSocket connections.
    #
    # @return [String] The Bearer token (format: "Bearer <token>")
    # @raise [StandardError] If authentication fails
    #
    # @example
    #   token = ApiManager.token
    #   # => "Bearer eyJraWQiOiIyMDIxMDQyNjE4..."
    #
    #   # Use with WebSocket connection
    #   headers = { 'Authorization' => token }
    #
    def token
      raise "Authenticator not set. Call set_authenticator first." if @iam_authenticator.nil?

      begin
        # Create an empty request hash - the SDK will populate it
        request = {}

        # Force token refresh by setting force_refresh option
        # This ensures we get a fresh token, especially important for reconnections
        # The IBM Cloud SDK Core will check token expiration and refresh if needed
        @iam_authenticator.authenticate(request)

        # The Ruby SDK puts the Authorization header directly in the request hash
        # Try both string and symbol keys for compatibility
        authorization = request["Authorization"] || request[:Authorization]

        raise StandardError.new("Authentication succeeded but no Authorization header was set. Request: #{request.inspect}") if authorization.nil?

        # Log token info for debugging (first 20 chars only for security)
        token_preview = authorization[0..19] if authorization
        puts "🔑 Token obtained: #{token_preview}..."

        authorization
      rescue StandardError => e
        error_msg = "Failed to get authentication token for websocket connect. Error: #{e.message}"
        puts "❌ Token error details: #{e.class.name} - #{e.message}"
        puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}" if e.backtrace
        raise StandardError.new(error_msg)
      end
    end

    ##
    # Post metering data to the App Configuration service
    #
    # Sends usage metrics for feature and property evaluations to the billing server.
    #
    # @param url [String] The full metering endpoint URL
    # @param data [Hash] The metering data to send
    # @param apikey [String] The API key for authentication
    # @return [IBMCloudSdkCore::DetailedResponse] The HTTP response
    # @raise [StandardError] If the request fails
    #
    # @example
    #   data = {
    #     'collection_id' => 'coll-1',
    #     'environment_id' => 'env-prod',
    #     'usages' => [...]
    #   }
    #   response = ApiManager.post_metering(url, data, apikey)
    #
    def post_metering(url, metering_data, _apikey)
      require "json"

      # Extract the path from the full URL
      uri = URI.parse(url)
      path = uri.path

      # The IBM Cloud Ruby SDK's BaseService.request method signature:
      # request(method:, url:, headers: nil, params: nil, json: nil, data: nil)
      # For POST with JSON body, we should use the 'json' parameter (not 'body')
      client = base_service_client

      client.request(
        method: "POST",
        url: path,
        headers: headers(true),
        json: metering_data # Use 'json' parameter for JSON body
      )
    end

    ##
    # Get the IAM Authenticator instance
    #
    # @return [IBMCloudSdkCore::IamAuthenticator, nil] The IAM authenticator or nil if not set
    #
    # @example
    #   authenticator = ApiManager.iam_authenticator
    #   if authenticator
    #     puts "Authenticator is configured"
    #   end
    #
    attr_reader :iam_authenticator

    ##
    # Reset the ApiManager state (useful for testing)
    #
    # Clears all cached instances, forcing re-initialization on next use.
    #
    # @return [void]
    #
    # @example
    #   ApiManager.reset!
    #   # All instances cleared, will be recreated on next access
    #
    def reset!
      @iam_authenticator = nil
      @base_service_client = nil
      @url_builder = nil
    end
  end
end
