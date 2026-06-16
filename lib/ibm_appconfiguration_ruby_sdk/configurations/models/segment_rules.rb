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

# SegmentRules model for App Configuration service
class SegmentRules
  attr_reader :rules, :rule_id, :value, :order, :rollout_type, :rollout_percentage, :rollout_configuration

  # @param segment_rules [Hash] Segment rules configuration hash
  def initialize(segment_rules)
    require_relative "../internal/constants"

    @rules = segment_rules[:rules]
    @rule_id = segment_rules[:rule_id]
    @value = segment_rules[:value]
    @order = segment_rules[:order]
    @rollout_type = segment_rules.key?(:rollout_type) ? segment_rules[:rollout_type] : Constants::MANUAL

    if segment_rules[:rollout_configuration]
      @rollout_configuration = segment_rules[:rollout_configuration]
    else
      @rollout_percentage = segment_rules.key?(:rollout_percentage) ? segment_rules[:rollout_percentage] : 100
    end
  end

  # @return [Array<Hash>] Rules array
  def get_rules
    @rules || []
  end

  # @return [Boolean, String, Numeric] Rule value
  def get_value
    @value || ""
  end

  # @return [Integer] Rule order
  def get_order
    @order
  end

  # @return [Integer] Rollout percentage
  def get_rollout_percentage
    @rollout_percentage
  end
end
