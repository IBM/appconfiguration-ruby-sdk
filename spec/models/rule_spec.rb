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

require "spec_helper"

RSpec.describe IbmAppconfigurationRubySdk::Rule do
  def rule(operator, values, attribute_name = "email")
    described_class.new(attribute_name: attribute_name, operator: operator, values: values)
  end

  describe "#operator_check string operators" do
    it "handles endsWith / notEndsWith" do
      expect(rule("endsWith", ["ibm.com"]).operator_check("john@ibm.com", "ibm.com")).to be(true)
      expect(rule("notEndsWith", ["ibm.com"]).operator_check("john@ibm.com", "ibm.com")).to be(false)
    end

    it "handles startsWith / notStartsWith" do
      expect(rule("startsWith", ["john"]).operator_check("john@ibm.com", "john")).to be(true)
      expect(rule("notStartsWith", ["john"]).operator_check("jane@ibm.com", "john")).to be(true)
    end

    it "handles contains / notContains" do
      expect(rule("contains", ["ibm"]).operator_check("john@ibm.com", "ibm")).to be(true)
      expect(rule("notContains", ["xyz"]).operator_check("john@ibm.com", "xyz")).to be(true)
    end

    it "handles is / isNot" do
      expect(rule("is", ["a"]).operator_check("a", "a")).to be(true)
      expect(rule("isNot", ["b"]).operator_check("a", "b")).to be(true)
    end
  end

  describe "#operator_check numeric operators" do
    it "compares numbers correctly" do
      expect(rule("greaterThan", [10]).operator_check(20, 10)).to be(true)
      expect(rule("lesserThan", [10]).operator_check(5, 10)).to be(true)
      expect(rule("greaterThanEquals", [10]).operator_check(10, 10)).to be(true)
      expect(rule("lesserThanEquals", [10]).operator_check(10, 10)).to be(true)
    end

    it "compares numeric 'is' by value" do
      expect(rule("is", [10]).operator_check(10, 10)).to be(true)
      expect(rule("is", [11]).operator_check(10, 11)).to be(false)
    end
  end

  describe "#operator_check edge cases" do
    it "returns false for nil key or value" do
      expect(rule("is", ["a"]).operator_check(nil, "a")).to be(false)
      expect(rule("is", ["a"]).operator_check("a", nil)).to be(false)
    end

    it "returns false for unknown operators" do
      expect(rule("unknownOp", ["a"]).operator_check("a", "a")).to be(false)
    end
  end

  describe "#evaluate_rule" do
    it "supports string and symbol attribute keys" do
      r = rule("endsWith", ["ibm.com"])
      expect(r.evaluate_rule("email" => "john@ibm.com")).to be(true)
      expect(r.evaluate_rule(email: "john@ibm.com")).to be(true)
    end

    it "returns false when the attribute is missing" do
      expect(rule("endsWith", ["ibm.com"]).evaluate_rule(name: "john")).to be(false)
    end

    it "uses ALL semantics for negative operators" do
      r = rule("notEndsWith", ["ibm.com", "test.com"])
      expect(r.evaluate_rule(email: "john@example.com")).to be(true)
      expect(r.evaluate_rule(email: "john@ibm.com")).to be(false)
    end

    it "uses ANY semantics for positive operators" do
      r = rule("endsWith", ["ibm.com", "test.com"])
      expect(r.evaluate_rule(email: "john@test.com")).to be(true)
    end

    it "returns false when entity attributes are not a hash" do
      expect(rule("is", ["a"]).evaluate_rule("not-a-hash")).to be(false)
    end
  end
end
