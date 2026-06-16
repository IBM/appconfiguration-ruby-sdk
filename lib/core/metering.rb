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
require 'json'
require 'thread'
require_relative '../configurations/internal/logger'
require_relative '../configurations/internal/constants'
require_relative 'api_manager'

# Copyright 2021 IBM Corp. All Rights Reserved.
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

##
# Metering module tracks feature and property evaluation metrics and sends them
# to the App Configuration billing server at regular intervals (every 10 minutes).
#
# This implementation uses Ruby's native Mutex and Thread for thread safety.
#
# @example Basic usage
#   metering = Metering.instance
#   metering.set_metering_url(url, apikey)
#   metering.add_metering(guid, env_id, coll_id, entity_id, segment_id, feature_id, nil)
#
class Metering
  include Singleton

  # Delimiter for composite keys (Unit Separator character)
  DELIMITER = "\u001F"
  
  # Metering interval in seconds (10 minutes)
  METERING_INTERVAL = 600

  ##
  # Initialize the Metering singleton
  def initialize
    @metering_feature_data = {}
    @metering_property_data = {}
    @data_mutex = Mutex.new
    @metering_url = nil
    @apikey = nil
    @metering_thread = nil
    @logger = Logger.instance
    start_metering_thread
  end

  ##
  # Inner class for storing metering records
  # Tracks count and latest evaluation time with thread-safe operations
  class MeteringRecord
    ##
    # Initialize a new metering record
    #
    # @param time [String] Initial evaluation time in ISO 8601 format
    def initialize(time)
      @count = 1
      @latest_time = time
      @mutex = Mutex.new
    end

    ##
    # Increment the count and update latest time if newer
    #
    # @param new_time [String] New evaluation time in ISO 8601 format
    def increment(new_time)
      @mutex.synchronize do
        @count += 1
        @latest_time = new_time if new_time > @latest_time
      end
    end

    ##
    # Get the current count (thread-safe)
    #
    # @return [Integer] The evaluation count
    def get_count
      @mutex.synchronize { @count }
    end

    ##
    # Get the latest evaluation time (thread-safe)
    #
    # @return [String] The latest evaluation time
    def get_latest_time
      @mutex.synchronize { @latest_time }
    end
  end

  ##
  # Set the metering URL and API key
  #
  # @param url [String] The metering endpoint URL
  # @param apikey [String] The API key for authentication
  def set_metering_url(url, apikey)
    @metering_url = url
    @apikey = apikey
  end

  ##
  # Add a metering record for a feature or property evaluation
  #
  # @param guid [String] The service instance GUID
  # @param environment_id [String] The environment ID
  # @param collection_id [String] The collection ID
  # @param entity_id [String] The entity ID
  # @param segment_id [String] The segment ID
  # @param feature_id [String, nil] The feature ID (nil for property evaluations)
  # @param property_id [String, nil] The property ID (nil for feature evaluations)
  def add_metering(guid, environment_id, collection_id, entity_id, segment_id, feature_id, property_id)
    key = build_composite_key(
      guid,
      environment_id,
      collection_id,
      feature_id || property_id,
      entity_id,
      segment_id
    )

    data_map = feature_id ? @metering_feature_data : @metering_property_data
    evaluation_time = current_datetime

    @data_mutex.synchronize do
      if data_map.key?(key)
        data_map[key].increment(evaluation_time)
      else
        data_map[key] = MeteringRecord.new(evaluation_time)
      end
    end
  end

  ##
  # Build a composite key from components
  # Handles nil values by converting to empty strings
  #
  # @param guid [String] The service instance GUID
  # @param env_id [String] The environment ID
  # @param coll_id [String] The collection ID
  # @param modify_key [String] The feature or property ID
  # @param entity_id [String] The entity ID
  # @param segment_id [String] The segment ID
  # @return [String] The composite key
  def build_composite_key(guid, env_id, coll_id, modify_key, entity_id, segment_id)
    [
      guid || '',
      env_id || '',
      coll_id || '',
      modify_key || '',
      entity_id || '',
      segment_id || ''
    ].join(DELIMITER)
  end

  ##
  # Parse a composite key into its components
  #
  # @param composite_key [String] The composite key to parse
  # @return [Array<String>] Array of key components
  def parse_composite_key(composite_key)
    composite_key.split(DELIMITER, -1)
  end

  ##
  # Get current datetime in ISO 8601 format
  #
  # @return [String] Current datetime string
  def current_datetime
    Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  end

  ##
  # Send metering data to the server
  # Atomically swaps data maps to avoid blocking new evaluations
  #
  # @return [Hash] The request body that was sent
  def send_metering
    # Atomic swap of data maps
    current_feature_data = nil
    current_property_data = nil

    @data_mutex.synchronize do
      current_feature_data = @metering_feature_data
      current_property_data = @metering_property_data
      @metering_feature_data = {}
      @metering_property_data = {}
    end

    return {} if current_feature_data.empty? && current_property_data.empty?

    result = {}

    build_request_body(current_feature_data, result, 'feature_id') unless current_feature_data.empty?
    build_request_body(current_property_data, result, 'property_id') unless current_property_data.empty?

    result.each do |guid, data_array|
      data_array.each do |json|
        count = json['usages'].length
        if count > 25
          send_split_metering(json, count)
        else
          send_to_server(json)
        end
      end
    end

    result
  end

  ##
  # Build the request body from metering data
  #
  # @param send_metering_data [Hash] The metering data to process
  # @param result [Hash] The result hash to populate
  # @param key [String] Either 'feature_id' or 'property_id'
  def build_request_body(send_metering_data, result, key)
    send_metering_data.each do |composite_key, metering_record|
      key_parts = parse_composite_key(composite_key)
      next if key_parts.length != 6

      guid = key_parts[0]
      environment_id = key_parts[1]
      collection_id = key_parts[2]
      feature_or_property_id = key_parts[3]
      entity_id = key_parts[4]
      segment_id = key_parts[5]

      # Get or create GUID entry
      result[guid] ||= []

      # Find or create collection
      collection = find_or_create_collection(
        result[guid],
        environment_id,
        collection_id
      )

      # Create usage object
      usage = {
        key => feature_or_property_id,
        'entity_id' => entity_id == Constants::DEFAULT_ENTITY_ID ? nil : entity_id,
        'segment_id' => segment_id == Constants::DEFAULT_SEGMENT_ID ? nil : segment_id,
        'evaluation_time' => metering_record.get_latest_time,
        'count' => metering_record.get_count
      }

      collection['usages'] << usage
    end
  end

  ##
  # Find or create a collection in the GUID array
  #
  # @param guid_array [Array] Array of collections for a GUID
  # @param environment_id [String] The environment ID
  # @param collection_id [String] The collection ID
  # @return [Hash] The collection hash
  def find_or_create_collection(guid_array, environment_id, collection_id)
    # Look for existing collection
    collection = guid_array.find do |coll|
      coll['environment_id'] == environment_id &&
        coll['collection_id'] == collection_id
    end

    # Create new if not found
    unless collection
      collection = {
        'collection_id' => collection_id,
        'environment_id' => environment_id,
        'usages' => []
      }
      guid_array << collection
    end

    collection
  end

  ##
  # Send split metering data for large payloads
  # Splits payloads with >25 usages into chunks of 10
  #
  # @param data [Hash] The collection data to split
  # @param count [Integer] Total number of usages
  def send_split_metering(data, count)
    lim = 0
    sub_usages_array = data['usages']

    while lim < count
      end_index = [lim + Constants::DEFAULT_USAGE_LIMIT, count].min
      collections_map = {
        'collection_id' => data['collection_id'],
        'environment_id' => data['environment_id'],
        'usages' => []
      }

      (lim...end_index).each do |i|
        collections_map['usages'] << sub_usages_array[i]
      end

      send_to_server(collections_map)
      lim += Constants::DEFAULT_USAGE_LIMIT
    end
  end

  ##
  # Send metering data to the server
  # Retries on 429 and 5xx errors with exponential backoff
  #
  # @param data [Hash] The metering data to send
  # @param retry_count [Integer] Current retry attempt (for exponential backoff)
  def send_to_server(data, retry_count = 0)
    return unless @metering_url && @apikey

    begin
      response = ApiManager.post_metering(@metering_url, data, @apikey)

      # Success - no logging needed for normal operation
      if response.status != Constants::STATUS_CODE_ACCEPTED
        @logger.warning("Metering response status: #{response.status}")
      end
    rescue StandardError => e
      @logger.error("Exception occurred while sending metering data: #{e.message}")

      # Extract status code from the error
      status = nil
      if e.respond_to?(:status)
        status = e.status
      elsif e.message =~ /status_code.*=>.*(\d{3})/
        status = $1.to_i
      end

      # Retry on 429 (rate limit) or 5xx (server errors) with exponential backoff
      # Don't retry on 4xx client errors (except 429)
      max_retries = 3
      if (status == 429 || (status && status >= 500 && status <= 599)) && retry_count < max_retries
        # Exponential backoff: 30s, 60s, 120s
        backoff_time = 30 * (2 ** retry_count)
        @logger.info("Retrying metering request in #{backoff_time}s (attempt #{retry_count + 1}/#{max_retries})")
        
        Thread.new do
          sleep(backoff_time)
          send_to_server(data, retry_count + 1)
        end
      elsif retry_count >= max_retries
        @logger.error("Max retries (#{max_retries}) reached for metering data. Giving up.")
      end
    end
  end

  ##
  # Start the background metering thread
  # Sends metering data every 10 minutes
  def start_metering_thread
    @metering_thread = Thread.new do
      loop do
        sleep(METERING_INTERVAL)
        begin
          send_metering
        rescue StandardError => e
          @logger.error("Error in metering thread: #{e.message}")
        end
      end
    end

    @metering_thread.abort_on_exception = false
  end

  ##
  # Stop the metering thread
  def stop_metering_thread
    @metering_thread&.kill
    @metering_thread = nil
  end

  ##
  # Cleanup method - stops thread and sends remaining data
  def cleanup
    stop_metering_thread
    send_metering # Send any remaining data
  end
end
