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

RSpec.describe IbmAppconfigurationRubySdk::SegmentRules do
  let(:segment_rule_hash) do
    {
      rules: [{ segments: ["seg1"] }],
      rule_id: "rule-1",
      value: "$default",
      order: 1,
      rollout_percentage: 50
    }
  end

  subject(:segment_rule) { described_class.new(segment_rule_hash) }

  it "exposes the basic getters" do
    expect(segment_rule.get_rules).to eq([{ segments: ["seg1"] }])
    expect(segment_rule.get_value).to eq("$default")
    expect(segment_rule.get_order).to eq(1)
    expect(segment_rule.get_rollout_percentage).to eq(50)
    expect(segment_rule.rule_id).to eq("rule-1")
  end

  it "defaults rollout_type to MANUAL" do
    expect(segment_rule.rollout_type).to eq(IbmAppconfigurationRubySdk::Constants::MANUAL)
  end

  it "defaults rollout_percentage to 100 when not provided" do
    sr = described_class.new(segment_rule_hash.reject { |k, _| k == :rollout_percentage })
    expect(sr.get_rollout_percentage).to eq(100)
  end

  context "with a progressive rollout configuration" do
    subject(:segment_rule) do
      described_class.new(
        segment_rule_hash.merge(
          rollout_type: IbmAppconfigurationRubySdk::Constants::PROGRESSIVE,
          rollout_configuration: { start_at: "2020-01-01T00:00:00Z", phases: [{ percentage: 100 }] }
        ).reject { |k, _| k == :rollout_percentage }
      )
    end

    it "stores the rollout configuration" do
      expect(segment_rule.rollout_configuration).not_to be_nil
      expect(segment_rule.rollout_type).to eq(IbmAppconfigurationRubySdk::Constants::PROGRESSIVE)
    end
  end
end
