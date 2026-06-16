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
require "json"
require_relative "models/feature"
require_relative "models/property"
require_relative "models/segment"
require_relative "models/segment_rules"
require_relative "models/secret_property"
require_relative "internal/file_manager"
require_relative "internal/logger"
require_relative "internal/constants"
require_relative "internal/utils"
require_relative "internal/websocket_client/websocket_client"
require_relative "internal/retry_manager/config_fetcher"
require_relative "../core/url_builder"
require_relative "../core/metering"

##
# Internal client to handle the configuration
class ConfigurationHandler
  include Singleton

  def initialize
    @collection_id = nil
    @environment_id = nil
    @guid = nil
    @is_connected = true
    @live_update = true
    @bootstrap_file = nil
    @persistent_cache_directory = nil

    @feature_map = {}
    @property_map = {}
    @segment_map = {}
    @secret_map = {}
    @rollout_config_map = {}
    @all_feature_flags = []

    @logger = Logger.instance
    @file_manager = FileManager.instance
    @websocket_client = nil

    # Configuration update listener (single listener, matches Java SDK)
    @configuration_update_listener = nil
  end

  ##
  # Initialize the configuration handler
  # @param region [String] The region
  # @param guid [String] The GUID
  # @param apikey [String] The API key
  # @param use_private_endpoint [Boolean] Whether to use private endpoint
  def init(region, guid, apikey, use_private_endpoint)
    @guid = guid
    @region = region
    @apikey = apikey
    @use_private_endpoint = use_private_endpoint

    # Initialize UrlBuilder
    url_builder = UrlBuilder.instance
    url_builder.region = region
    url_builder.guid = guid
    url_builder.apikey = apikey
    url_builder.use_private_endpoint = use_private_endpoint

    # Initialize ApiManager
    ApiManager.set_authenticator

    # Initialize Metering
    metering_url = "#{url_builder.base_service_url}/apprapp/events/v1/instances/#{guid}/usage"
    Metering.instance.set_metering_url(metering_url, apikey)
  end

  ##
  # Cleanup resources
  def cleanup
    Metering.instance.cleanup
    @websocket_client&.disconnect
  end

  ##
  # Load configurations to cache
  # @param data [Hash] Configuration data
  def load_configurations_to_cache(data)
    return unless data

    if data[:features]
      features = data[:features]
      @all_feature_flags = features
      @feature_map = {}
      @rollout_config_map = {}

      features.each do |feature|
        feature_obj = Feature.new(feature)
        @feature_map[feature[:feature_id]] = feature_obj

        # Parse feature-level progressive rollout
        if feature_obj.rollout_configuration
          @rollout_config_map[feature[:feature_id]] =
            parse_rollout_configuration_phases(feature_obj.rollout_configuration)
        end

        # Parse segment-level progressive rollout
        next unless feature[:segment_rules].is_a?(Array)

        feature[:segment_rules].each do |segment_rule|
          segment_rule_obj = SegmentRules.new(segment_rule)
          if segment_rule_obj.rollout_configuration
            key = "#{feature[:feature_id]}#{Constants::DELIMITER}#{segment_rule[:rule_id]}"
            @rollout_config_map[key] = parse_rollout_configuration_phases(segment_rule_obj.rollout_configuration)
          end
        end
      end
    end

    if data[:properties]
      properties = data[:properties]
      @property_map = {}
      properties.each do |property|
        @property_map[property[:property_id]] = Property.new(property)
      end
    end

    if data[:segments]
      segments = data[:segments]
      @segment_map = {}
      segments.each do |segment|
        @segment_map[segment[:segment_id]] = Segment.new(segment)
      end
    end

    # Notify listener after configurations are loaded
    notify_configuration_update_listener
  end

  ##
  # Write to persistent storage
  # @param file_data [Hash] File data to persist
  def write_to_persistent_storage(file_data)
    return unless @persistent_cache_directory

    json = JSON.generate(file_data)
    file_path = File.join(@persistent_cache_directory, "appconfiguration.json")
    @file_manager.store_files(json, file_path)
  end

  ##
  # Report error
  # @param error [String, Exception] Error message or exception
  def report_error(error)
    error_msg = error.is_a?(Exception) ? error.message : error.to_s
    @logger.error(error_msg)
  end

  def format_config(configurations, _environment_id, _collection_id)
    # TODO: Implement actual formatting logic
    configurations
  end

  ##
  # Set context for configuration
  # @param collection_id [String] Collection ID
  # @param environment_id [String] Environment ID
  # @param options [Hash] Additional options
  def set_context(collection_id, environment_id, options = {})
    @collection_id = collection_id
    @environment_id = environment_id
    @persistent_cache_directory = options[:persistent_cache_directory]
    @bootstrap_file = options[:bootstrap_file]
    @live_update = options[:live_config_update_enabled]

    # TODO: Initialize evaluation events and metric events
    # evaluationEvents.init(@guid, @environment_id)
    # metricEvents.init(@guid, @environment_id)

    persistent_cache_read = false
    error_reading_bootstrap_config = false

    # Handle persistent cache directory
    if @persistent_cache_directory
      @logger.info("persistent cache directory path is: #{@persistent_cache_directory}")
      file_path = File.join(@persistent_cache_directory, "appconfiguration.json")
      persistent_cache = @file_manager.read_persistent_cache_configurations(file_path)

      unless persistent_cache.empty?
        configurations = extract_configurations(JSON.parse(persistent_cache), @environment_id, @collection_id)
        load_configurations_to_cache(configurations)
        persistent_cache_read = true
      end

      # Check write permissions
      begin
        # Test if directory is writable
        File.write(File.join(@persistent_cache_directory, ".write_test"), "")
        File.delete(File.join(@persistent_cache_directory, ".write_test"))
      rescue StandardError => e
        report_error("ERROR: No write permission for persistent cache directory. #{e}")
      end
    end

    # Handle bootstrap file
    if @bootstrap_file
      if @persistent_cache_directory
        # If persistent cache directory exists
        if persistent_cache_read
          # Persistent cache was read, emit event if not live update
          # TODO: emit(APPCONFIGURATION_CLIENT_EMITTER) unless @live_update
        else
          # Only read bootstrap if persistent cache wasn't read
          begin
            @logger.info("reading configurations from bootstrap file: #{@bootstrap_file}")
            bootstrap_config = @file_manager.read_bootstrap_configurations_from_file(@bootstrap_file)
            configurations = extract_configurations(JSON.parse(bootstrap_config), @environment_id, @collection_id)
            load_configurations_to_cache(configurations)
            write_to_persistent_storage(format_config(configurations, @environment_id, @collection_id))
            # TODO: emit event if not live update
            # emit(APPCONFIGURATION_CLIENT_EMITTER) unless @live_update
          rescue StandardError => e
            report_error(e)
          end
        end
      else
        # No persistent cache directory, just read bootstrap
        @logger.info("reading configurations from bootstrap file: #{@bootstrap_file}")
        begin
          bootstrap_config = @file_manager.read_bootstrap_configurations_from_file(@bootstrap_file)
          configurations = extract_configurations(JSON.parse(bootstrap_config, symbolize_names: true),
                                                  @environment_id, @collection_id)
          load_configurations_to_cache(configurations)
          # TODO: emit(APPCONFIGURATION_CLIENT_EMITTER) unless @live_update
        rescue StandardError => e
          report_error(e) unless @live_update
          @logger.error(e.message.to_s)
          error_reading_bootstrap_config = true
        end
      end
    end

    # Implement live update logic
    return unless @live_update

    @logger.info("Live update enabled - fetching configurations from API...")

    # Track whether to start background retry
    start_background_retry = false

    # Create config fetcher instance
    config_fetcher = ConfigFetcher.new(
      collection_id: @collection_id,
      environment_id: @environment_id,
      logger: @logger
    )

    # Fetch configurations from API
    fetch_result = config_fetcher.fetch

    if fetch_result[:ok]
      @logger.info("✅ Successfully fetched configurations from API")

      # Display raw API response
      # @logger.info("=" * 80)
      # @logger.info("📡 RAW API RESPONSE:")
      # @logger.info("-" * 80)
      require "json"
      # @logger.info(JSON.pretty_generate(fetch_result[:data]))
      # @logger.info("=" * 80)

      # Process and load configurations
      begin
        # Convert string keys to symbol keys
        symbolized_data = symbolize_keys(fetch_result[:data])

        @logger.info("🔍 Symbolized data keys: #{symbolized_data.keys.inspect}")
        @logger.info("🔍 Environments: #{symbolized_data[:environments]&.length || 0}")
        @logger.info("🔍 Collections: #{symbolized_data[:collections]&.length || 0}")

        # Extract configurations using utils.rb method
        @logger.info("🔍 About to call extract_configurations")
        @logger.info("   Environment ID: #{@environment_id}")
        @logger.info("   Collection ID: #{@collection_id}")
        @logger.info("   Symbolized data has #{symbolized_data[:environments]&.first&.dig(:features)&.length || 0} features in first environment")

        extracted_config = extract_configurations(
          symbolized_data,
          @environment_id,
          @collection_id
        )

        @logger.info("📊 Extracted config - Features: #{extracted_config[:features]&.length || 0}, Properties: #{extracted_config[:properties]&.length || 0}, Segments: #{extracted_config[:segments]&.length || 0}")

        if extracted_config[:features] && extracted_config[:features].empty?
          @logger.warning("⚠️  WARNING: 0 features extracted but API returned features!")
          @logger.warning("   This suggests an issue in extract_configurations or validate_resource")
        end

        # Load to cache using existing method
        load_configurations_to_cache(extracted_config)

        @logger.info("📊 Loaded to cache - Features: #{@feature_map.length}, Properties: #{@property_map.length}, Segments: #{@segment_map.length}")

        # Write to persistent storage if configured
        if @persistent_cache_directory
          formatted_config = format_config(extracted_config, @environment_id, @collection_id)
          write_to_persistent_storage(formatted_config)
        end

        @logger.info("✅ Configurations loaded successfully")
      rescue StandardError => e
        @logger.error("❌ Failed to process configurations: #{e.message}")
        @logger.error(e.backtrace.first(3).join("\n"))
      end
    else
      # Failed to fetch from API
      status_code = fetch_result[:status]
      err_msg = "Status code: #{status_code}. Message: Failed to fetch the configurations from remote server."

      # Check for client-side errors (4xx except 429)
      report_error(err_msg) if status_code >= 400 && status_code < 500 && status_code != 429

      # Check if we have fallback configurations (persistent cache or bootstrap)
      if persistent_cache_read
        message = "Loaded the configurations from the persistent cache into the application."
        @logger.info("#{err_msg} #{message}")
        start_background_retry = true
        # TODO: emit event
      elsif @bootstrap_file && !error_reading_bootstrap_config
        message = "Loaded the configurations from the bootstrap file: #{@bootstrap_file} into the application."
        @logger.info("#{err_msg} #{message}")
        start_background_retry = true
        # TODO: emit event
      else
        # No fallback available
        @logger.error("❌ No configurations available - neither from API nor from cache/bootstrap")
        report_error(err_msg)
      end
    end

    # Start WebSocket client for live updates
    @logger.info("🔌 Starting WebSocket client for live updates...")
    begin
      # Get required parameters from UrlBuilder
      url_builder = UrlBuilder.instance

      # Set @guid from url_builder if not already set
      @guid ||= url_builder.guid

      @websocket_client = WebSocketClient.new(
        region: url_builder.region,
        guid: @guid,
        apikey: url_builder.apikey,
        collection_id: @collection_id,
        environment_id: @environment_id,
        start_background_retry: start_background_retry
      )

      @websocket_client.connect
      @logger.info("✅ WebSocket client started successfully")
    rescue StandardError => e
      @logger.error("❌ Failed to start WebSocket client: #{e.message}")
      @logger.error(e.backtrace.first(3).join("\n"))
    end
  end

  def track(event_key, entity_id)
    # TODO: Implement tracking logic
  end

  ##
  # Get feature by ID
  # @param feature_id [String] Feature ID
  # @return [Feature, nil] Feature object or nil
  def get_feature(feature_id)
    return @feature_map[feature_id] if @feature_map.key?(feature_id)

    @logger.error("Invalid feature id - #{feature_id}")
    nil
  end

  ##
  # Get property by ID
  # @param property_id [String] Property ID
  # @return [Property, nil] Property object or nil
  def get_property(property_id)
    return @property_map[property_id] if @property_map.key?(property_id)

    @logger.error("Invalid property id - #{property_id}")
    nil
  end

  ##
  # Get secret property
  # @param property_id [String] Property ID
  # @param secrets_manager_service [Object] Secrets manager service
  # @return [SecretProperty, nil] Secret property or nil
  def get_secret(property_id, secrets_manager_service)
    property_obj = get_property(property_id)
    if property_obj
      if property_obj.get_property_data_type == Constants::SECRETREF
        @secret_map[property_id] = secrets_manager_service
        return SecretProperty.new(property_id)
      end
      @logger.error("Invalid operation: getSecret() cannot be called on a #{property_obj.get_property_data_type} property.")
      return nil
    end
    nil
  end

  ##
  # Get segment by ID
  # @param segment_id [String] Segment ID
  # @return [Segment, nil] Segment object or nil
  def get_segment(segment_id)
    return @segment_map[segment_id] if @segment_map.key?(segment_id)

    @logger.error("Invalid segment id - #{segment_id}")
    nil
  end

  ##
  # Evaluate segment
  # @param segment_key [String] Segment key
  # @param entity_attributes [Hash] Entity attributes
  # @return [Boolean] Evaluation result
  def evaluate_segment(segment_key, entity_attributes)
    if @segment_map.key?(segment_key)
      segment_obj = @segment_map[segment_key]
      return segment_obj.evaluate_rule(entity_attributes)
    end
    nil
  end

  ##
  # Parse rules
  # @param segment_rules [Array] Segment rules
  # @return [Hash] Parsed rules
  def parse_rules(segment_rules)
    rules_map = {}
    segment_rules.each do |rules|
      rules_map[rules[:order]] = SegmentRules.new(rules)
    end
    rules_map
  end

  ##
  # Get rollout percentage for progressive rollout
  # @param feature [Feature] Feature object
  # @param segment_rule [SegmentRules, nil] Segment rule object (nil for feature-level)
  # @param entity_id [String] Entity ID
  # @return [Integer] Rollout percentage
  def get_rollout_percentage(feature, segment_rule, _entity_id)
    if segment_rule
      # Segment-level rollout
      if segment_rule.rollout_configuration || (segment_rule.rollout_type && segment_rule.rollout_type == Constants::PROGRESSIVE)
        rollout_hash = if segment_rule.rollout_percentage == Constants::DEFAULT_ROLLOUT_PERCENTAGE
                         @rollout_config_map[feature.feature_id]
                       else
                         @rollout_config_map["#{feature.feature_id}#{Constants::DELIMITER}#{segment_rule.rule_id}"]
                       end

        return 0 unless rollout_hash

        segment_rule.rollout_configuration[:start_at]
        current_time_ms = (Time.now.to_f * 1000).to_i
        # Find the entry with timestamp <= current time (sorted hash)
        percentage = 0
        rollout_hash.each do |timestamp, pct|
          break if timestamp > current_time_ms

          percentage = pct
        end
        percentage

      else
        # Manual rollout
        segment_rule.rollout_percentage == Constants::DEFAULT_ROLLOUT_PERCENTAGE ? feature.rollout_percentage : segment_rule.rollout_percentage
      end
    else
      # Feature-level rollout
      return feature.rollout_percentage || 100 unless feature.rollout_configuration

      rollout_hash = @rollout_config_map[feature.feature_id]
      return 0 unless rollout_hash

      feature.rollout_configuration[:start_at]
      current_time_ms = (Time.now.to_f * 1000).to_i
      # Find the entry with timestamp <= current time (sorted hash)
      percentage = 0
      rollout_hash.each do |timestamp, pct|
        break if timestamp > current_time_ms

        percentage = pct
      end
      percentage

    end
  end

  ##
  # Evaluate rules
  # @param rules_map [Hash] Rules map
  # @param entity_attributes [Hash] Entity attributes
  # @param feature [Feature, nil] Feature object
  # @param property [Property, nil] Property object
  # @param entity_id [String] Entity ID
  # @return [Hash] Evaluation result
  def evaluate_rules(rules_map, entity_attributes, feature, property, entity_id = nil)
    result_dict = {
      evaluated_segment_id: Constants::DEFAULT_SEGMENT_ID,
      value: nil,
      is_enabled: false,
      details: {}
    }

    begin
      # For each rule in the targeting
      (1..rules_map.keys.length).each do |index|
        segment_rule = rules_map[index]

        next unless segment_rule.get_rules.length.positive?

        segment_rule.get_rules.each do |rule|
          segments = rule[:segments]

          next unless segments&.length&.positive?

          # For each segment in a rule
          segments.each do |segment_key|
            # Check whether the entityAttributes satisfies all the rules of that segment
            next unless evaluate_segment(segment_key, entity_attributes)

            segment_name = @segment_map[segment_key].name
            result_dict[:evaluated_segment_id] = segment_key
            result_dict[:details][:segment_name] = segment_name

            if feature
              # evaluateRules was called for feature flag
              segment_level_rollout_percentage = get_rollout_percentage(feature, segment_rule, entity_id)

              # Check whether the entityId is eligible for segment rollout
              if segment_level_rollout_percentage == 100 ||
                 (entity_id && get_normalized_value("#{entity_id}:#{feature.feature_id}") < segment_level_rollout_percentage)
                # Since the entityId is eligible for segment rollout, return inherited or overridden value
                result_dict[:value] = if segment_rule.get_value == Constants::DEFAULT_FEATURE_VALUE
                                        feature.enabled_value # Return the inherited value
                                      else
                                        segment_rule.get_value # Return the overridden value
                                      end
                result_dict[:details][:value_type] = "SEGMENT_VALUE"
                result_dict[:is_enabled] = true
                result_dict[:details][:rollout_percentage_applied] = true
              else
                result_dict[:value] = feature.disabled_value
                result_dict[:is_enabled] = false
                result_dict[:details][:value_type] = "DISABLED_VALUE"
                result_dict[:details][:rollout_percentage_applied] = false
              end
            else
              # evaluateRules was called for property
              result_dict[:value] = if segment_rule.get_value == Constants::DEFAULT_PROPERTY_VALUE
                                      property.value
                                    else
                                      segment_rule.get_value
                                    end
              result_dict[:details][:value_type] = "SEGMENT_VALUE"
            end
            return result_dict
          end
        end
      end
    rescue StandardError => e
      @logger.error("RuleEvaluation #{e}")
      result_dict[:value] = nil
      result_dict[:is_enabled] = false
      result_dict[:details][:value_type] = "ERROR"
      result_dict[:details][:error_type] = e.message
      return result_dict
    end

    # Since entityAttributes did not satisfy any of the targeting rules
    if feature
      # evaluateRules was called for feature flag
      # Check whether the entityId is eligible for default rollout
      rollout_percentage = get_rollout_percentage(feature, nil, entity_id)

      if rollout_percentage == 100 ||
         (entity_id && get_normalized_value("#{entity_id}:#{feature.feature_id}") < rollout_percentage)
        result_dict[:value] = feature.enabled_value
        result_dict[:is_enabled] = true
        result_dict[:details][:value_type] = "ENABLED_VALUE"
        result_dict[:details][:rollout_percentage_applied] = true
      else
        result_dict[:value] = feature.disabled_value
        result_dict[:is_enabled] = false
        result_dict[:details][:value_type] = "DISABLED_VALUE"
        result_dict[:details][:rollout_percentage_applied] = false
      end
    else
      # evaluateRules was called for property
      result_dict[:value] = property.value
      result_dict[:details][:value_type] = "DEFAULT_VALUE"
    end

    result_dict
  end

  ##
  # Record evaluation
  # @param feature_id [String] Feature ID
  # @param property_id [String] Property ID
  # @param entity_id [String] Entity ID
  # @param segment_id [String] Segment ID
  def record_evaluation(feature_id, property_id, entity_id, segment_id)
    Metering.instance.add_metering(
      @guid,
      @environment_id,
      @collection_id,
      entity_id || Constants::DEFAULT_ENTITY_ID,
      segment_id || Constants::DEFAULT_SEGMENT_ID,
      feature_id,
      property_id
    )
  end

  ##
  # Feature evaluation
  # @param feature [Feature] Feature object
  # @param entity_id [String] Entity ID
  # @param entity_attributes [Hash] Entity attributes
  # @return [Hash] Evaluation result with keys: value, is_enabled, details
  def feature_evaluation(feature, entity_id, entity_attributes)
    result_dict = {
      evaluated_segment_id: Constants::DEFAULT_SEGMENT_ID,
      value: nil,
      is_enabled: false,
      details: {}
    }

    begin
      # Step 1: Check if feature flag is enabled
      unless feature.enabled
        result_dict[:details][:value_type] = "DISABLED_VALUE"
        return {
          value: feature.disabled_value,
          is_enabled: false,
          details: result_dict[:details]
        }
      end

      # Step 2: Check if feature has segment rules (targeting) and valid entity attributes
      if feature.segment_rules&.length&.positive? &&
         entity_attributes.is_a?(Hash) && entity_attributes.keys.length.positive?
        # Evaluate targeting rules
        rules_map = parse_rules(feature.segment_rules)
        result_dict = evaluate_rules(rules_map, entity_attributes, feature, nil, entity_id)
        return {
          value: result_dict[:value],
          is_enabled: result_dict[:is_enabled],
          details: result_dict[:details]
        }
      end

      # Step 3: No targeting rules - apply default rollout percentage
      # Check if entity_id qualifies for rollout
      rollout_percentage = get_rollout_percentage(feature, nil, entity_id)
      normalized_value = get_normalized_value("#{entity_id}:#{feature.feature_id}")

      if rollout_percentage == 100 ||
         normalized_value < rollout_percentage
        result_dict[:details][:value_type] = "ENABLED_VALUE"
        result_dict[:details][:rollout_percentage_applied] = true
        return {
          value: feature.enabled_value,
          is_enabled: true,
          details: result_dict[:details]
        }
      end

      # Step 4: Entity doesn't qualify for rollout
      result_dict[:details][:value_type] = "DISABLED_VALUE"
      result_dict[:details][:rollout_percentage_applied] = false
      {
        value: feature.disabled_value,
        is_enabled: false,
        details: result_dict[:details]
      }
    ensure
      # Always record evaluation for metering
      record_evaluation(feature.feature_id, nil, entity_id, result_dict[:evaluated_segment_id])
    end
  end

  ##
  # Property evaluation
  # @param property [Property] Property object
  # @param entity_id [String] Entity ID
  # @param entity_attributes [Hash] Entity attributes
  # @return [Hash] Evaluation result
  def property_evaluation(property, entity_id, entity_attributes)
    result_dict = {
      evaluated_segment_id: Constants::DEFAULT_SEGMENT_ID,
      value: nil,
      details: {}
    }

    begin
      # Check whether the property is configured with any targeting definition
      # and then check whether the user has passed valid entityAttributes JSON before we evaluate
      if property.segment_rules&.length&.positive? &&
         entity_attributes.is_a?(Hash) && entity_attributes.keys.length.positive?
        rules_map = parse_rules(property.segment_rules)
        result_dict = evaluate_rules(rules_map, entity_attributes, nil, property, entity_id)
        return {
          value: result_dict[:value],
          details: result_dict[:details]
        }
      end

      result_dict[:details][:value_type] = "DEFAULT_VALUE"
      {
        value: property.value,
        details: result_dict[:details]
      }
    ensure
      # Record evaluation for metering
      record_evaluation(nil, property.property_id, entity_id, result_dict[:evaluated_segment_id])
    end
  end

  ##
  # Get features
  # @return [Hash] Hash of features
  def get_features
    @feature_map
  end

  ##
  # Get properties
  # @return [Hash] Hash of properties
  def get_properties
    @property_map
  end

  ##
  # Check if connected
  # @return [Boolean] Connection status
  def connected?
    @is_connected
  end

  ##
  # Set live update status
  # @param live_update [Boolean] Live update status
  def set_live_update(live_update)
    @live_update = live_update
  end

  ##
  # Set bootstrap file
  # @param bootstrap_file [String] Path to bootstrap file
  def set_bootstrap_file(bootstrap_file)
    @bootstrap_file = bootstrap_file
  end

  ##
  # Set persistent cache directory
  # @param directory [String] Cache directory path
  def set_persistent_cache_directory(directory)
    @persistent_cache_directory = directory
  end

  ##
  # Register configuration update listener
  # Registers a callback block that will be invoked when configurations are updated.
  # Only one listener can be registered at a time (matches Java SDK behavior).
  # Calling this method multiple times will replace the previous listener.
  # @param block [Proc] Callback block to be invoked on configuration updates
  # @example
  #   handler.register_configuration_update_listener do
  #     puts "Configurations updated!"
  #   end
  def register_configuration_update_listener(&block)
    if block_given?
      @configuration_update_listener = block
      @logger.log("Configuration update listener registered")
    else
      @logger.warning("No block provided to register_configuration_update_listener")
    end
  end

  ##
  # Notify the registered configuration update listener
  # This method is called internally when configurations are updated.
  # The listener is invoked safely - exceptions are caught to prevent breaking the update flow.
  # @private
  def notify_configuration_update_listener
    return unless @configuration_update_listener

    begin
      @logger.log("Notifying configuration update listener")
      @configuration_update_listener.call
    rescue StandardError => e
      @logger.error("Error in configuration update listener: #{e.message}")
      @logger.error(e.backtrace.first(3).join("\n"))
    end
  end

  ##
  # Get the secrets map
  # @return [Hash] Hash of secret manager instances mapped by property_id
  def get_secrets_map
    @secret_map
  end
end
