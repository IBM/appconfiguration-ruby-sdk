# frozen_string_literal: true

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

module IbmAppconfigurationRubySdk
  ##
  # Metadata about *how* an evaluation reached its result.
  #
  # @!attribute [r] value_type
  #   @return [String] One of "ENABLED_VALUE", "DISABLED_VALUE", "SEGMENT_VALUE",
  #     "DEFAULT_VALUE", or "ERROR"
  # @!attribute [r] rollout_percentage_applied
  #   @return [Boolean, nil] Whether a rollout-percentage gate was applied
  # @!attribute [r] segment_name
  #   @return [String, nil] Human-readable name of the matching segment (if any)
  # @!attribute [r] error_type
  #   @return [String, nil] Error message when value_type is "ERROR"
  EvaluationDetails = Struct.new(
    :value_type,
    :rollout_percentage_applied,
    :segment_name,
    :error_type,
    keyword_init: true
  )

  ##
  # The result of evaluating a feature flag or remote property for a given entity.
  #
  # @example Feature flag
  #   result = client.get_feature("my-flag").get_current_value("user-1", {})
  #   puts result.value      # => true / false / String / Numeric
  #   puts result.enabled    # => true / false  (feature flags only; nil for properties)
  #   puts result.details.value_type  # => "ENABLED_VALUE"
  #
  # @!attribute [r] value
  #   @return [Object] The resolved value of the feature flag or property
  # @!attribute [r] enabled
  #   @return [Boolean, nil] Whether the feature flag is enabled (nil for properties)
  # @!attribute [r] details
  #   @return [EvaluationDetails] Metadata about how the value was resolved
  EvaluationResult = Struct.new(:value, :enabled, :details, keyword_init: true)
end
