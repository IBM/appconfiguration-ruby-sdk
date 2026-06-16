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

require_relative '../internal/constants'
require_relative '../internal/logger'

##
# Defines the model of a Property defined in App Configuration service.
class Property
  attr_reader :name, :property_id, :type, :format, :value, :segment_rules

  ##
  # Initialize a new Property instance
  # @param property [Hash] properties hash that contains all the properties
  def initialize(property)
    @name = property[:name]
    @property_id = property[:property_id]
    @type = property[:type]
    @format = property[:format] # will be nil for boolean & numeric datatypes
    @value = property[:value]
    @segment_rules = property[:segment_rules]
  end

  ##
  # Get the Property name
  # @return [String] The Property name
  def get_property_name
    @name || ''
  end

  ##
  # Get the Property id
  # @return [String] The Property Id
  def get_property_id
    @property_id || ''
  end

  ##
  # Get the Property data type
  # @return [String] string named BOOLEAN/STRING/NUMERIC
  def get_property_data_type
    @type || ''
  end

  ##
  # Get the Property data format
  # applicable only for STRING datatype property.
  #
  # @return [String, nil] string named TEXT/JSON/YAML
  def get_property_data_format
    # Format will be `nil` for Boolean & Numeric properties
    # If the Format is nil for a String type, we default it to TEXT
    @format = 'TEXT' if @format.nil? && @type == 'STRING'
    @format
  end

  ##
  # Get the evaluated value of the property.
  #
  # @param entity_id [String] Id of the Entity.
  # This will be a string identifier related to the Entity against which the property is evaluated.
  # For example, an entity might be an instance of an app that runs on a mobile device, a microservice that runs on the cloud, or a component of infrastructure that runs that microservice.
  # For any entity to interact with App Configuration, it must provide a unique entity ID.
  #
  # @param entity_attributes [Hash] A hash consisting of the attribute name and their values that defines the specified entity.
  # This is an optional parameter if the property is not configured with any targeting definition. If the targeting is configured, then entity_attributes should be provided for the rule evaluation.
  # An attribute is a parameter that is used to define a segment. The SDK uses the attribute values to determine if the
  # specified entity satisfies the targeting rules, and returns the appropriate property value.
  #
  # @return [Hash, nil] Returns a hash containing evaluated value & detailed reason.
  # The evaluated value will be either the default property value or its overridden value based on the evaluation. The data type of returned value matches that of property.
  # Returns nil if entity_id is invalid.
  #
  # @example
  #   property = app_config_client.get_property('discount')
  #   if property
  #     result = property.get_current_value(entity_id, entity_attributes)
  #
  #     # Access the evaluated value & details as shown below
  #     # result[:value]
  #     # result[:details]
  #   end
  def get_current_value(entity_id, entity_attributes = {})
    if entity_id.nil? || entity_id.to_s.strip.empty?
      logger = Logger.instance
      logger.error("Property evaluation: #{Constants::INVALID_ENTITY_ID} get_current_value")
      return nil
    end

    require_relative '../configuration_handler'
    configuration_handler_instance = ConfigurationHandler.instance
    configuration_handler_instance.property_evaluation(self, entity_id, entity_attributes)
  end
end
