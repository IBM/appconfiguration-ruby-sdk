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

require_relative "../constants"
require_relative "../logger"

# Feature model for App Configuration service
module IbmAppconfigurationRubySdk
class Feature
  attr_reader :name, :feature_id, :type, :format, :disabled_value, :enabled_value,
              :enabled, :rollout_type, :rollout_percentage, :rollout_configuration,
              :segment_rules, :experiment

  # @param feature [Hash] Feature configuration hash
  def initialize(feature)
    @name = feature[:name]
    @feature_id = feature[:feature_id]
    @type = feature[:type]
    @format = feature[:format]
    @disabled_value = feature[:disabled_value]
    @enabled_value = feature[:enabled_value]
    @enabled = feature[:enabled]
    @rollout_type = feature.key?(:rollout_type) ? feature[:rollout_type] : Constants::MANUAL

    if feature[:rollout_configuration]
      @rollout_configuration = feature[:rollout_configuration]
    else
      @rollout_percentage = feature.key?(:rollout_percentage) ? feature[:rollout_percentage] : 100
    end

    @segment_rules = feature[:segment_rules]
    @experiment = feature[:experiment]
  end

  # @return [String, nil] Feature data format (TEXT/JSON/YAML)
  def data_format
    @format = "TEXT" if @format.nil? && @type == "STRING"
    @format
  end

  # @return [Boolean] Feature enabled state
  def enabled?
    @enabled
  end

  ##
  # Evaluates and returns the feature flag value for the given entity.
  #
  # @param entity_id [String] Id of the Entity.
  #   This will be a string identifier related to the Entity against which the feature is evaluated.
  #   For example, an entity might be an instance of an app that runs on a mobile device, a microservice
  #   that runs on the cloud, or a component of infrastructure that runs that microservice.
  #   For any entity to interact with App Configuration, it must provide a unique entity ID.
  #
  # @param entity_attributes [Hash] A hash consisting of the attribute name and their values that defines
  #   the specified entity. This is an optional parameter if the feature flag is not configured with any
  #   targeting definition. If the targeting is configured, then entity_attributes should be provided for
  #   the rule evaluation. An attribute is a parameter that is used to define a segment. The SDK uses the
  #   attribute values to determine if the specified entity satisfies the targeting rules, and returns the
  #   appropriate feature flag value.
  #
  # @return [EvaluationResult, nil] Returns an {EvaluationResult} with:
  #   - +result.value+ — the resolved value (type matches the feature flag's type)
  #   - +result.enabled+ — whether the feature flag is enabled for this entity
  #   - +result.details+ — an {EvaluationDetails} explaining how the value was reached
  #   Returns nil if entity_id is invalid.
  #
  # @example
  #   feature = app_config_client.get_feature('discount')
  #   if feature
  #     result = feature.get_current_value(entity_id, entity_attributes)
  #     result.value       # => true / false / String / Numeric
  #     result.enabled     # => true / false
  #     result.details.value_type  # => "ENABLED_VALUE" / "DISABLED_VALUE" / "SEGMENT_VALUE"
  #   end
  #
  #   # Note: While an experiment is running, result.enabled == true indicates
  #   # that the entity was part of the experiment audience.
  #
  def get_current_value(entity_id, entity_attributes = {})
    if entity_id.nil? || entity_id.to_s.strip.empty?
      logger = Logger.instance
      logger.error("Feature flag evaluation: #{Constants::INVALID_ENTITY_ID} get_current_value")
      return nil
    end

    require_relative "../configuration_handler"
    configuration_handler_instance = ConfigurationHandler.current_instance
    configuration_handler_instance.feature_evaluation(self, entity_id, entity_attributes)
  end
end
end
