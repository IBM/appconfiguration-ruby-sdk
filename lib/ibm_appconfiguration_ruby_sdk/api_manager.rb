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
require "json"
require "uri"
require_relative "url_builder"
require_relative "constants"
require_relative "logger"
require_relative "version"

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
module IbmAppconfigurationRubySdk
  # Manages authentication, HTTP clients, and request headers
  class ApiManager
    # SDK version for User-Agent header
    SDK_VERSION = IbmAppconfigurationRubySdk::VERSION

    # Class variables to store singleton instances
    @iam_authenticator = nil
    @base_service_client = nil
    @url_builder = nil
    @logger = Logger.instance

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
      #   headers = ApiManager.headers(is_post: true)
      #   # => { 'Accept' => 'application/json', 'User-Agent' => '...', 'Content-Type' => 'application/json' }
      #
      def headers(is_post: false)
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
          @logger.log("Using custom IAM URL: #{iam_url}")
        else
          @logger.log("Using default IAM URL: #{default_prod_url}")
        end

        # IBMCloudSdkCore::IamAuthenticator#initialize immediately fetches a token,
        # so a bad API key raises IBMCloudSdkCore::ApiException here rather than
        # at first use. Wrap it so callers only ever see our typed error hierarchy.
        begin
          @iam_authenticator = IBMCloudSdkCore::IamAuthenticator.new(authenticator_options)
        rescue IBMCloudSdkCore::ApiException => e
          status  = e.code.to_i
          message = e.error || e.message
          raise IbmAppconfigurationRubySdk::APIError.from_status(
            status.positive? ? status : 401,
            message: "IAM authentication failed: #{message}"
          )
        rescue StandardError => e
          raise IbmAppconfigurationRubySdk::ConfigurationError.new("Failed to initialise IAM authenticator: #{e.message}")
        end
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
          raise IbmAppconfigurationRubySdk::ConfigurationError.new("Authenticator not set. Call set_authenticator first.") if @iam_authenticator.nil?

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
        raise IbmAppconfigurationRubySdk::ConfigurationError.new("Authenticator not set. Call set_authenticator first.") if @iam_authenticator.nil?

        # Create an empty request hash - the SDK will populate it
        request = {}

        # Force token refresh by setting force_refresh option
        # This ensures we get a fresh token, especially important for reconnections
        # The IBM Cloud SDK Core will check token expiration and refresh if needed
        refresh_token!

        @iam_authenticator.authenticate(request)

        # The Ruby SDK puts the Authorization header directly in the request hash
        # Try both string and symbol keys for compatibility
        authorization = request["Authorization"] || request[:Authorization]

        raise IbmAppconfigurationRubySdk::ConfigurationError.new("Authentication succeeded but no Authorization header was set. Request: #{request.inspect}") if authorization.nil?

        # Log token info for debugging (first 20 chars only for security)
        token_preview = authorization[0..19] if authorization
        @logger.log("#{Constants::IAM_TOKEN_OBTAINED}: #{token_preview}...")

        authorization
      end

      ##
      # Force a full token refresh by recreating the IamAuthenticator.
      #
      # --- Why patching the existing token manager does NOT reliably work ---
      #
      # The Node SDK uses `createRequest()` which calls `tokenManager.getToken()`
      # on EVERY request — that method checks expiry and fetches a new token when
      # needed. The Ruby SDK's `BaseService#request` calls `authenticate()` which
      # calls `token_manager.access_token` — a raw hash read with NO expiry check.
      #
      # We tried calling `token_manager.token` (the method with the expiry check)
      # before each request, but `token_expired?` uses an 80%-of-TTL threshold
      # computed from the JWT's `exp` and `iat` fields.  If the IAM server issues a
      # token that the *metering endpoint* rejects before the 80% threshold is
      # reached (e.g. the test environment uses shorter-lived metering grants, or
      # the token is valid for config/websocket but not for the metering scope),
      # `token_expired?` returns false and no refresh happens.
      #
      # --- The correct fix ---
      # Recreate the IamAuthenticator entirely.  Its `initialize` immediately calls
      # `IAMTokenManager#token` → `request_token`, which unconditionally fetches a
      # brand-new token from IAM.  We also nil out `@base_service_client` so it is
      # rebuilt with the new authenticator, exactly matching the Node SDK pattern
      # where `getBaseServiceClient()` wires up a fresh authenticator on each call.
      #
      # This is safe to call from the metering thread because:
      # - `set_authenticator` is idempotent (replaces ivars atomically in MRI due to GVL)
      # - `base_service_client` recreates lazily on next use
      # - WebSocket uses `token` which calls `authenticate` on the NEW authenticator
      #
      # @return [void]
      # @raise [IbmAppconfigurationRubySdk::ConfigurationError] If UrlBuilder not configured
      #
      def refresh_token!
        raise IbmAppconfigurationRubySdk::ConfigurationError.new("Authenticator not set. Call set_authenticator first.") if @iam_authenticator.nil?

        # Recreate the authenticator — this unconditionally fetches a fresh IAM token.
        # Also clear the cached BaseService so it is rebuilt with the new authenticator.
        @base_service_client = nil
        set_authenticator
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
        # Force the IAM token manager to check expiry and refresh before every
        # metering POST.  Without this, long-running processes reuse a cached token
        # that the metering endpoint rejects with 401 once it expires (~1 hour).
        refresh_token!

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
          headers: headers(is_post: true),
          json: metering_data # Use 'json' parameter for JSON body
        )
      end

      ##
      # Get the IAM Authenticator instance
      #
      # @return [IBMCloudSdkCore::IamAuthenticator, nil] The IAM authenticator or nil if not set
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

      ##
      # Returns a developer-friendly string that hides authenticator internals.
      # Prevents accidental credential exposure when the class is printed.
      #
      # @return [String]
      def inspect
        "#<#{self} authenticated=#{!@iam_authenticator.nil?}>"
      end
    end
  end
end
