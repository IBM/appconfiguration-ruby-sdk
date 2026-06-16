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

require_relative 'rule'

# Segment model for App Configuration service
class Segment
  attr_reader :name, :segment_id, :rules

  # @param segment_list [Hash] Segment configuration hash
  def initialize(segment_list)
    @name = segment_list[:name]
    @segment_id = segment_list[:segment_id]
    @rules = segment_list[:rules] || []
  end

  # Evaluates all segment rules against entity attributes
  #
  # @param entity_attributes [Hash] Entity attributes hash
  # @return [Boolean] True if all rules pass
  def evaluate_rule(entity_attributes)
    @rules.all? do |rule|
      Rule.new(rule).evaluate_rule(entity_attributes)
    end
  end
end
