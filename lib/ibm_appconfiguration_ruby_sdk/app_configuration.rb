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

require "singleton"
require_relative "configurations/configuration_handler"
require_relative "configurations/internal/logger"
require_relative "configurations/internal/constants"
require_relative "core/url_builder"

module IbmAppconfigurationRubySdk
  # AppConfiguration client class implementing singleton pattern
  class AppConfiguration
    include Singleton

    # Region constants
    REGION_US_SOUTH = "us-south"
    REGION_EU_GB = "eu-gb"
    REGION_AU_SYD = "au-syd"
    REGION_US_EAST = "us-east"
    REGION_EU_DE = "eu-de"
    REGION_CA_TOR = "ca-tor"
    REGION_JP_TOK = "jp-tok"
    REGION_JP_OSA = "jp-osa"

    class << self
      ##
      # Get the current instance without creating a new one
      # @return [AppConfiguration] The current instance
      # @raise [RuntimeError] If instance doesn't exist
      def current_instance
        raise Constants::SINGLETON_EXCEPTION unless @singleton__instance__

        instance
      end

      ##
      # Override the default App Configuration URL
      # This method should be invoked before the SDK initialization
      # NOTE: To be used for development purposes only
      # @param url [String] The base service URL
      def override_service_url(url)
        return unless url

        url_builder = UrlBuilder.instance
        url_builder.set_base_service_url(url)
      end
    end

    def initialize
      @is_initialized = false
      @is_initialized_config = false
      @use_private_endpoint = false
      @configuration_handler = nil
      @logger = Logger.instance
      @url_builder = UrlBuilder.instance
    end

    ##
    # Initialize the SDK to connect with your App Configuration service instance
    # @param region [String] Region name where the App Configuration service instance is created
    # @param guid [String] GUID of the App Configuration service
    # @param apikey [String] API key of the App Configuration service
    # @raise [RuntimeError] If any required parameter is missing or invalid
    def init(region, guid, apikey)
      # init is a SDK initialization method. It is expected to be called only once.
      # This condition ensures the init inputs are taken only once even if called multiple times.
      return if @is_initialized

      unless region && guid && apikey
        if !region
          report_error(Constants::REGION_ERROR)
        elsif !guid
          report_error(Constants::GUID_ERROR)
        else
          report_error(Constants::APIKEY_ERROR)
        end
      end

      @configuration_handler = ConfigurationHandler.instance
      @configuration_handler.init(region, guid, apikey, @use_private_endpoint)
      @is_initialized = true
    end

    ##
    # Set the context of the SDK
    # @param collection_id [String] ID of the collection created in App Configuration service instance
    # @param environment_id [String] ID of the environment created in App Configuration service instance
    # @param options [Hash] Optional configuration parameters
    # @option options [String] :persistent_cache_directory Directory path for persistent cache
    # @option options [String] :bootstrap_file Absolute path of configuration file
    # @option options [Boolean] :live_config_update_enabled Enable live configuration updates (default: true)
    # @raise [RuntimeError] If init was not called or parameters are invalid
    def set_context(collection_id, environment_id, options = {})
      # setContext is also a SDK initialization method. It is expected to be called only once.
      # This condition ensures the setContext inputs are taken only once even if called multiple times.
      return if @is_initialized_config

      report_error(Constants::COLLECTION_ID_ERROR) unless @is_initialized

      report_error(Constants::COLLECTION_ID_VALUE_ERROR) unless collection_id

      report_error(Constants::ENVIRONMENT_ID_VALUE_ERROR) unless environment_id

      default_options = {
        persistent_cache_directory: nil,
        bootstrap_file: nil,
        live_config_update_enabled: true
      }

      if options
        report_error(Constants::INVALID_OPTIONS_PARAMETER.to_s) unless options.is_a?(Hash)

        if options.key?(:persistent_cache_directory)
          given_dir_path = options[:persistent_cache_directory]
          if given_dir_path.is_a?(String) && !given_dir_path.empty?
            default_options[:persistent_cache_directory] = given_dir_path
          else
            report_error("#{Constants::PERSISTENT_CACHE_OPTION_ERROR} #{given_dir_path}")
          end
        end

        if options.key?(:bootstrap_file)
          given_file_path = options[:bootstrap_file]
          if given_file_path.is_a?(String) && !given_file_path.empty? && File.extname(given_file_path) == ".json"
            default_options[:bootstrap_file] = given_file_path
          else
            report_error("#{Constants::BOOTSTRAP_FILEPATH_OPTION_ERROR} #{given_file_path}")
          end
        end

        if options.key?(:live_config_update_enabled)
          given_flag_value = options[:live_config_update_enabled]
          if [true, false].include?(given_flag_value)
            default_options[:live_config_update_enabled] = given_flag_value
          else
            report_error("#{Constants::LIVE_CONFIG_UPDATE_OPTION_ERROR} #{given_flag_value}")
          end
        end

        report_error(Constants::CONFIGURATION_FILE_NOT_FOUND_ERROR) if default_options[:live_config_update_enabled] == false && default_options[:bootstrap_file].nil?
      end

      @is_initialized_config = true
      @configuration_handler = ConfigurationHandler.instance
      @configuration_handler.set_context(collection_id, environment_id, default_options)
    end

    ##
    # Set the SDK to connect to App Configuration service using a private endpoint
    # This function must be called before calling the init function
    # @param use_private_endpoint_param [Boolean] Set to true to use private endpoint (default: false)
    def use_private_endpoint(use_private_endpoint_param)
      if [true, false].include?(use_private_endpoint_param)
        @use_private_endpoint = use_private_endpoint_param
        return
      end
      @logger.error(Constants::INPUT_PARAMETER_NOT_BOOLEAN)
    end

    ##
    # Returns the Feature object with the details of the feature specified by the feature_id
    # @param feature_id [String] The Feature ID
    # @return [Feature, nil] Feature object or nil if invalid
    def get_feature(feature_id)
      return @configuration_handler.get_feature(feature_id) if @is_initialized && @is_initialized_config

      @logger.error(Constants::COLLECTION_INIT_ERROR)
      nil
    end

    ##
    # Returns all features associated with the collection_id
    # @return [Hash, nil] Hash of all features or nil
    def get_features
      return @configuration_handler.get_features if @is_initialized && @is_initialized_config

      @logger.error(Constants::COLLECTION_INIT_ERROR)
      nil
    end

    ##
    # Returns the Property object with the details of the property specified by the property_id
    # @param property_id [String] The Property ID
    # @return [Property, nil] Property object or nil if invalid
    def get_property(property_id)
      return @configuration_handler.get_property(property_id) if @is_initialized && @is_initialized_config

      @logger.error(Constants::COLLECTION_INIT_ERROR)
      nil
    end

    ##
    # Returns all properties associated with the collection_id
    # @return [Hash, nil] Hash of all properties or nil
    def get_properties
      return @configuration_handler.get_properties if @is_initialized && @is_initialized_config

      @logger.error(Constants::COLLECTION_INIT_ERROR)
      nil
    end

    ##
    # Returns the SecretProperty object corresponding to the given property_id
    # @param property_id [String] ID of the secret property from App Configuration
    # @param secrets_manager_service [Object] Secret Manager client object
    # @return [SecretProperty, nil] SecretProperty object or nil
    def get_secret(property_id, secrets_manager_service)
      if @is_initialized && @is_initialized_config
        return @configuration_handler.get_secret(property_id, secrets_manager_service) if secrets_manager_service

        @logger.error(Constants::INVALID_SECRET_MANAGER_CLIENT_MESSAGE)
        return nil
      end
      @logger.error(Constants::COLLECTION_INIT_ERROR)
      nil
    end

    ##
    # Record custom metric events for an entity_id while running an experiment
    # @param event_key [String] SDK event key
    # @param entity_id [String] The entity ID
    def track(event_key, entity_id)
      return @configuration_handler.track(event_key, entity_id) if @is_initialized && @is_initialized_config

      @logger.error(Constants::COLLECTION_INIT_ERROR)
      nil
    end

    ##
    # Enable or disable the logger
    # By default, logger is disabled
    # @param value [Boolean] Enable (true) or disable (false) debug logging
    def set_debug(value = false)
      Logger.set_debug(value)
    end

    ##
    # Check if the SDK is connected to the service
    # @return [Boolean] Connection status
    def connected?
      return @configuration_handler.connected? if @is_initialized && @is_initialized_config

      false
    end

    ##
    # Register a configuration update listener
    # The listener will be invoked whenever configurations are updated (initial load or live updates).
    # Only one listener can be registered at a time - calling this method multiple times will replace the previous listener.
    # @param block [Proc] Callback block to be invoked on configuration updates
    # @example
    #   app_config = IbmAppconfigurationRubySdk::AppConfiguration.instance
    #   app_config.register_configuration_update_listener do
    #     puts "Configurations updated!"
    #     feature = app_config.get_feature('my-feature')
    #     # React to configuration changes
    #   end
    # @return [void]
    def register_configuration_update_listener(&block)
      if @is_initialized && @is_initialized_config
        @configuration_handler.register_configuration_update_listener(&block)
        return
      end
      @logger.error(Constants::COLLECTION_INIT_ERROR)
    end

    private

    ##
    # Report error and raise exception
    # @param error [String] Error message
    # @raise [RuntimeError] Always raises with the error message
    def report_error(error)
      @logger.error(error)
      raise error
    end
  end
end
