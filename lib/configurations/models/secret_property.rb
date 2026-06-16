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
# Defines the SecretProperty model.
class SecretProperty
  attr_reader :property_id

  ##
  # Initialize a new SecretProperty instance
  # @param property_id [String] Property identifier
  def initialize(property_id)
    @property_id = property_id
  end

  ##
  # Evaluate the value of the secret property.
  #
  # @param entity_id [String] Id of the Entity.
  # @param entity_attributes [Hash] A hash consisting of the attribute name and their values that defines the specified entity.
  #
  # @return [Object, nil] returns the response from the secret manager or nil if entity_id is invalid.
  # The returned value will be the actual secret value of the evaluated secret reference. The response contains the body, the headers, the status code, and the status text.
  # If an error occurs, it will be raised as an exception.
  def get_current_value(entity_id, entity_attributes = {})
    logger = Logger.instance

    if entity_id.nil? || entity_id.to_s.strip.empty?
      logger.error("SecretProperty evaluation: #{Constants::INVALID_ENTITY_ID} get_current_value")
      return nil
    end

    require_relative '../configuration_handler'
    configuration_handler_instance = ConfigurationHandler.instance
    
    # Get the property object
    property_obj = configuration_handler_instance.get_property(@property_id)
    return nil unless property_obj
    
    # Get the current value of the property (which contains the secret reference)
    property_current_val = property_obj.get_current_value(entity_id, entity_attributes)
    return nil unless property_current_val
    
    # Check if the property value contains a secret id
    if property_current_val[:value] && property_current_val[:value].is_a?(Hash) && property_current_val[:value].key?(:id)
      secret_id = property_current_val[:value][:id]
      
      # Get the secrets map from configuration handler
      secret_map = configuration_handler_instance.get_secrets_map
      secret_manager_obj = secret_map[@property_id]
      
      if secret_manager_obj
        # Call the get_secret method on the secret manager object
        # The caller is responsible for handling any exceptions
        return secret_manager_obj.get_secret(id: secret_id)
      else
        logger.error("SecretProperty Evaluation: Secret manager not configured for property: #{property_obj.get_property_name}")
        return nil
      end
    end
    
    logger.error("SecretProperty Evaluation: Secret Id is missing from the Property: #{property_obj.get_property_name}")
    nil
  end
end
