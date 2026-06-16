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

# Rule model for segment evaluation
class Rule
  attr_reader :attribute_name, :operator, :values

  # @param segment_rules [Hash] Rule configuration hash
  def initialize(segment_rules)
    @attribute_name = segment_rules[:attribute_name]
    @operator = segment_rules[:operator]
    @values = segment_rules[:values]
  end

  # @param key [Object] Attribute value to check
  # @param value [Object] Value to compare against
  # @return [Boolean] True if operator check passes
  def operator_check(key, value)
    return false if key.nil? || value.nil?

    case @operator
    when 'endsWith'
      /#{Regexp.escape(value.to_s)}$/i.match?(key.to_s)
    when 'notEndsWith'
      !/#{Regexp.escape(value.to_s)}$/i.match?(key.to_s)
    when 'startsWith'
      /^#{Regexp.escape(value.to_s)}/i.match?(key.to_s)
    when 'notStartsWith'
      !/^#{Regexp.escape(value.to_s)}/i.match?(key.to_s)
    when 'contains'
      key.to_s.include?(value.to_s)
    when 'notContains'
      !key.to_s.include?(value.to_s)
    when 'is'
      key.is_a?(Numeric) ? key.to_f == value.to_f : key.to_s == value.to_s
    when 'isNot'
      key.is_a?(Numeric) ? key.to_f != value.to_f : key.to_s != value.to_s
    when 'greaterThan'
      key.to_f > value.to_f
    when 'lesserThan'
      key.to_f < value.to_f
    when 'greaterThanEquals'
      key.to_f >= value.to_f
    when 'lesserThanEquals'
      key.to_f <= value.to_f
    else
      false
    end
  end

  # Evaluates rule against entity attributes
  #
  # @param entity_attributes [Hash] Entity attributes hash
  # @return [Boolean] True if evaluation passes
  def evaluate_rule(entity_attributes)
    return false unless entity_attributes.is_a?(Hash)
    
    # Support both string and symbol keys in entity_attributes
    # Check for string key first, then symbol key
    key = if entity_attributes.key?(@attribute_name)
            entity_attributes[@attribute_name]
          elsif entity_attributes.key?(@attribute_name.to_sym)
            entity_attributes[@attribute_name.to_sym]
          else
            return false
          end

    if ['isNot', 'notContains', 'notStartsWith', 'notEndsWith'].include?(@operator)
      @values.all? { |value| operator_check(key, value) }
    else
      @values.any? { |value| operator_check(key, value) }
    end
  end
end
