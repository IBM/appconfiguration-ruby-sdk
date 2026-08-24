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

RSpec.describe IbmAppconfigurationRubySdk::EvaluationDetails do
  it "can be constructed with all four keyword fields" do
    ed = described_class.new(
      value_type: "ENABLED_VALUE",
      rollout_percentage_applied: true,
      segment_name: "ibm employees",
      error_type: nil
    )
    expect(ed.value_type).to eq("ENABLED_VALUE")
    expect(ed.rollout_percentage_applied).to be(true)
    expect(ed.segment_name).to eq("ibm employees")
    expect(ed.error_type).to be_nil
  end

  it "defaults unspecified fields to nil" do
    ed = described_class.new(value_type: "DISABLED_VALUE")
    expect(ed.rollout_percentage_applied).to be_nil
    expect(ed.segment_name).to be_nil
    expect(ed.error_type).to be_nil
  end

  it "accepts an error type for error results" do
    ed = described_class.new(value_type: "ERROR", error_type: "entity_id missing")
    expect(ed.value_type).to eq("ERROR")
    expect(ed.error_type).to eq("entity_id missing")
  end
end

RSpec.describe IbmAppconfigurationRubySdk::EvaluationResult do
  let(:details) do
    IbmAppconfigurationRubySdk::EvaluationDetails.new(value_type: "ENABLED_VALUE")
  end

  it "can be constructed with value, enabled, and details" do
    result = described_class.new(value: true, enabled: true, details: details)
    expect(result.value).to be(true)
    expect(result.enabled).to be(true)
    expect(result.details).to eq(details)
  end

  it "allows enabled to be nil for property use-case" do
    result = described_class.new(value: "hello", enabled: nil, details: details)
    expect(result.enabled).to be_nil
  end

  it "allows value to be any type" do
    expect(described_class.new(value: 42,     enabled: nil, details: details).value).to eq(42)
    expect(described_class.new(value: "str",  enabled: nil, details: details).value).to eq("str")
    expect(described_class.new(value: false,  enabled: nil, details: details).value).to be(false)
  end

  it "defaults unspecified fields to nil" do
    result = described_class.new(value: "x")
    expect(result.enabled).to be_nil
    expect(result.details).to be_nil
  end
end
