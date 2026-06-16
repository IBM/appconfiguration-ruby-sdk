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

# frozen_string_literal: true

require 'set'
require 'murmurhash3'

# Validates feature/property belongs to collection if it contains collections else gives true as default
# @param resource [Hash] The resource (feature or property)
# @param collection [String] The collection ID
# @return [Boolean]
def validate_resource(resource, collection)
  # If collections is not present the resource data is coming from SDK APIs
  return true unless resource.key?(:collections)

  collections = resource[:collections]
  raise 'Improper collection format in resource data' unless collections.is_a?(Array)

  collections.any? { |coll| coll[:collection_id] == collection }
end

# Appends segment ids to the provided set
# @param resource [Hash] The resource (feature or property)
# @param segment_ids [Set] Set to store segment IDs
def append_segment_id(resource, segment_ids)
  return unless resource[:segment_rules]

  resource[:segment_rules].each do |segment_rule|
    segment_rule[:rules].each do |rule|
      rule[:segments].each do |segment_id|
        segment_ids.add(segment_id)
      end
    end
  end
end

# Prepares config data for extraction with validation
# @param data [Hash] Configuration data
# @param environment_id [String] Environment ID
# @return [Hash] Hash containing features, properties, and segments
def extract_environment_data(data, environment_id)
  unless data.key?(:segments) && data[:segments].is_a?(Array) &&
         data.key?(:environments) && data[:environments].is_a?(Array)
    raise 'Improper Data format present in configuration'
  end

  data[:environments].each do |environment|
    if environment[:environment_id] == environment_id
      result = {
        features: environment[:features] || [],
        properties: environment[:properties] || [],
        segments: data[:segments]
      }
      puts "🔍 extract_environment_data: Found environment '#{environment_id}'"
      puts "   Features: #{result[:features].length}"
      puts "   Properties: #{result[:properties].length}"
      puts "   Segments: #{result[:segments].length}"
      return result
    end
  end

  raise 'Matching environment not found in configuration'
end

# Returns object containing features, properties, segments after validation
# @param resource_data [Hash] Resource data containing features, properties, and segments
# @param collection [String] Collection ID
# @return [Hash] Hash containing validated features, properties, and segments
def extract_resources(resource_data, collection)
  features = []
  properties = []
  segments = []
  segment_ids = Set.new

  puts "🔍 DEBUG extract_resources:"
  puts "  Features in resource_data: #{resource_data[:features]&.length || 0}"
  puts "  Properties in resource_data: #{resource_data[:properties]&.length || 0}"
  puts "  Collection to match: #{collection}"

  # Appending features with validation to features array
  resource_data[:features].each do |feature|
    valid = validate_resource(feature, collection)
    if valid
      append_segment_id(feature, segment_ids)
      features << feature
    end
  end

  # Appending properties with validation to properties array
  resource_data[:properties].each do |property|
    valid = validate_resource(property, collection)
    if valid
      append_segment_id(property, segment_ids)
      properties << property
    end
  end

  # Appending only required segments to segments array and throw error if any required segment is absent
  resource_data[:segments].each do |segment|
    if segment_ids.include?(segment[:segment_id])
      segments << segment
      segment_ids.delete(segment[:segment_id])
    end
  end

  if segment_ids.size > 0
    raise "Required segment doesn't exist in provided segments"
  end

  {
    features: features,
    properties: properties,
    segments: segments
  }
end

# Unified parser for app-config data for new sdk-config format, export and promote data format
# @param configurations [Hash] Configuration JSON data (with symbol keys)
# @param environment [String] Environment ID
# @param collection [String] Collection ID
# @return [Hash] Hash containing features, properties, and segments
def extract_configurations(configurations, environment, collection)
  puts "🔍 extract_configurations called"
  puts "   Environment: #{environment}"
  puts "   Collection: #{collection}"
  
  # Check if data belongs to correct collection
  unless configurations.key?(:collections) && configurations[:collections].is_a?(Array)
    raise 'Improper/Missing collections in configuration'
  end

  match_found = false
  configurations[:collections].each do |coll|
    puts "   Checking collection: #{coll[:collection_id]}"
    if coll[:collection_id] == collection
      match_found = true
      break
    end
  end

  unless match_found
    raise 'Required collection not found in collections'
  end
  
  puts "   Collection match found!"

  # Data in SDK config/export/promote format
  config_data = extract_environment_data(configurations, environment)
  puts "   After extract_environment_data: features=#{config_data[:features]&.length}"
  
  result = extract_resources(config_data, collection)
  puts "   After extract_resources: features=#{result[:features]&.length}"
  
  result
rescue => e
  puts "❌ ERROR in extract_configurations: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  raise "Extraction of configurations failed with error:\n #{e.message}"
end

# Helper method to convert string keys to symbol keys recursively
# @param obj [Object] The object to convert
# @return [Object] The converted object with symbol keys
def symbolize_keys(obj)
  case obj
  when Hash
    obj.each_with_object({}) do |(key, value), result|
      result[key.to_sym] = symbolize_keys(value)
    end
  when Array
    obj.map { |item| symbolize_keys(item) }
  else
    obj
  end
end

##
# Compute hash using MurmurHash3
# @param str [String] String to hash
# @return [Integer] Hash value
def compute_hash(str)
  seed = 0
  MurmurHash3::V32.str_hash(str, seed)
end

##
# Get normalized value for rollout percentage calculation
# @param str [String] String to normalize
# @return [Integer] Normalized value (0-100)
def get_normalized_value(str)
  max_hash_value = 2**32
  normalizer = 100
  ((compute_hash(str).to_f / max_hash_value) * normalizer).floor
end

##
# Parse progressive rollout phases into a sorted hash for timestamp-to-percentage lookups.
# @param configuration [Hash] Rollout config with start_at and phases
# @return [Hash] Sorted hash mapping timestamp (ms) -> percentage
# @raise [ArgumentError] If configuration is invalid
def parse_rollout_configuration_phases(configuration)
  # Validate input
  unless configuration&.key?(:start_at) && configuration[:phases].is_a?(Array)
    raise ArgumentError, 'Invalid rollout configuration'
  end

  # Time unit multipliers (to milliseconds)
  multipliers = {
    'days' => 86_400_000,
    'hours' => 3_600_000,
    'minutes' => 60_000
  }

  # Parse start timestamp
  begin
    start_timestamp = Time.parse(configuration[:start_at]).to_i * 1000 # Convert to milliseconds
  rescue ArgumentError
    raise ArgumentError, "Invalid start_at: #{configuration[:start_at]}"
  end

  # Initialize result hash with initial entry
  result = { 0 => 0 }
  transition_time = start_timestamp

  # Process each phase
  configuration[:phases].each do |phase|
    if phase.is_a?(Hash) && phase.key?(:percentage) && phase[:percentage].is_a?(Numeric)
      result[transition_time] = phase[:percentage]

      # Calculate next transition time if duration is specified
      if phase[:duration] && phase[:duration_type] && multipliers[phase[:duration_type]]
        transition_time += multipliers[phase[:duration_type]] * phase[:duration]
      end
    end
  end

  # Return sorted hash (Ruby hashes maintain insertion order, so we sort by key)
  result.sort.to_h
end
