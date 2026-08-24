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

RSpec.describe IbmAppconfigurationRubySdk::Segment do
  let(:segment_hash) do
    {
      name: "ibm employees",
      segment_id: "ka761hap",
      rules: [
        { attribute_name: "email", operator: "endsWith", values: ["ibm.com", "in.ibm.com"] }
      ]
    }
  end

  subject(:segment) { described_class.new(segment_hash) }

  it "exposes name and segment_id" do
    expect(segment.name).to eq("ibm employees")
    expect(segment.segment_id).to eq("ka761hap")
  end

  it "evaluates to true when all rules pass" do
    expect(segment.evaluate_rule(email: "john@ibm.com")).to be(true)
  end

  it "evaluates to false when a rule fails" do
    expect(segment.evaluate_rule(email: "john@example.com")).to be(false)
  end

  it "requires ALL rules to pass" do
    multi = described_class.new(
      segment_hash.merge(
        rules: [
          { attribute_name: "email", operator: "endsWith", values: ["ibm.com"] },
          { attribute_name: "city", operator: "is", values: ["Bangalore"] }
        ]
      )
    )
    expect(multi.evaluate_rule(email: "john@ibm.com", city: "Bangalore")).to be(true)
    expect(multi.evaluate_rule(email: "john@ibm.com", city: "London")).to be(false)
  end
end
