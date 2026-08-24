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

RSpec.describe IbmAppconfigurationRubySdk::ConfigurationHandler do
  subject(:handler) { described_class.instance }

  # A timestamp comfortably in the past so progressive phases are active.
  past_start = "2020-01-01T00:00:00Z"
  # A timestamp far in the future so progressive rollout has not begun.
  future_start = "2999-01-01T00:00:00Z"

  let(:config) do
    {
      features: [
        { name: "Enabled", feature_id: "f-enabled", type: "BOOLEAN",
          enabled_value: true, disabled_value: false, enabled: true,
          rollout_percentage: 100, segment_rules: [] },

        { name: "Flag Off", feature_id: "f-off", type: "BOOLEAN",
          enabled_value: true, disabled_value: false, enabled: false,
          rollout_percentage: 100, segment_rules: [] },

        { name: "Rollout Zero", feature_id: "f-rollout-zero", type: "BOOLEAN",
          enabled_value: true, disabled_value: false, enabled: true,
          rollout_percentage: 0, segment_rules: [] },

        { name: "Segment Targeted", feature_id: "f-segment", type: "STRING",
          format: "TEXT", enabled_value: "default-value", disabled_value: "off-value",
          enabled: true, rollout_percentage: 100,
          segment_rules: [
            { rules: [{ segments: ["seg-ibm"] }], value: "segment-value",
              order: 1, rule_id: "rule-1", rollout_percentage: 100 }
          ] },

        { name: "Progressive Active", feature_id: "f-progressive", type: "BOOLEAN",
          enabled_value: true, disabled_value: false, enabled: true,
          rollout_type: IbmAppconfigurationRubySdk::Constants::PROGRESSIVE,
          rollout_configuration: { start_at: past_start, phases: [{ percentage: 100 }] },
          segment_rules: [] },

        { name: "Progressive Future", feature_id: "f-progressive-future", type: "BOOLEAN",
          enabled_value: true, disabled_value: false, enabled: true,
          rollout_type: IbmAppconfigurationRubySdk::Constants::PROGRESSIVE,
          rollout_configuration: { start_at: future_start, phases: [{ percentage: 100 }] },
          segment_rules: [] },

        { name: "Segment Progressive", feature_id: "f-seg-progressive", type: "BOOLEAN",
          enabled_value: true, disabled_value: false, enabled: true,
          rollout_percentage: 100,
          segment_rules: [
            { rules: [{ segments: ["seg-ibm"] }], value: "$default", order: 1,
              rule_id: "rule-1", rollout_type: IbmAppconfigurationRubySdk::Constants::PROGRESSIVE,
              rollout_percentage: 30,
              rollout_configuration: { start_at: past_start, phases: [{ percentage: 100 }] } }
          ] }
      ],
      properties: [
        { name: "Show Ad", property_id: "show-ad", type: "BOOLEAN", value: false, segment_rules: [] },
        { name: "Ad Targeted", property_id: "ad-targeted", type: "STRING", format: "TEXT",
          value: "default", segment_rules: [
            { rules: [{ segments: ["seg-ibm"] }], value: "overridden", order: 1, rule_id: "rule-1" }
          ] }
      ],
      segments: [
        { name: "ibm employees", segment_id: "seg-ibm",
          rules: [{ attribute_name: "email", operator: "endsWith", values: ["ibm.com"] }] }
      ]
    }
  end

  before { handler.load_configurations_to_cache(config) }

  describe "lookups" do
    it "returns loaded features, properties and segments" do
      expect(handler.get_feature("f-enabled")).to be_a(IbmAppconfigurationRubySdk::Feature)
      expect(handler.get_property("show-ad")).to be_a(IbmAppconfigurationRubySdk::Property)
      expect(handler.get_segment("seg-ibm")).to be_a(IbmAppconfigurationRubySdk::Segment)
    end

    it "returns nil for unknown ids" do
      expect(handler.get_feature("nope")).to be_nil
      expect(handler.get_property("nope")).to be_nil
      expect(handler.get_segment("nope")).to be_nil
    end
  end

  describe "#feature_evaluation" do
    it "returns the disabled value when the flag is turned off" do
      result = handler.feature_evaluation(handler.get_feature("f-off"), "e1", {})
      expect(result.enabled).to be(false)
      expect(result.value).to be(false)
      expect(result.details.value_type).to eq("DISABLED_VALUE")
    end

    it "returns the enabled value at 100% rollout" do
      result = handler.feature_evaluation(handler.get_feature("f-enabled"), "e1", {})
      expect(result.enabled).to be(true)
      expect(result.value).to be(true)
      expect(result.details.value_type).to eq("ENABLED_VALUE")
    end

    it "returns the disabled value at 0% rollout" do
      result = handler.feature_evaluation(handler.get_feature("f-rollout-zero"), "e1", {})
      expect(result.enabled).to be(false)
      expect(result.value).to be(false)
    end

    it "returns the overridden segment value for a matching entity" do
      result = handler.feature_evaluation(handler.get_feature("f-segment"), "e1", email: "john@ibm.com")
      expect(result.enabled).to be(true)
      expect(result.value).to eq("segment-value")
      expect(result.details.value_type).to eq("SEGMENT_VALUE")
    end

    it "falls back to the default rollout when the entity does not match a segment" do
      result = handler.feature_evaluation(handler.get_feature("f-segment"), "e1", email: "john@example.com")
      expect(result.enabled).to be(true)
      expect(result.value).to eq("default-value")
      expect(result.details.value_type).to eq("ENABLED_VALUE")
    end

    it "enables a feature whose progressive rollout is fully active" do
      result = handler.feature_evaluation(handler.get_feature("f-progressive"), "e1", {})
      expect(result.enabled).to be(true)
      expect(result.value).to be(true)
    end

    it "disables a feature whose progressive rollout has not started yet" do
      result = handler.feature_evaluation(handler.get_feature("f-progressive-future"), "e1", {})
      expect(result.enabled).to be(false)
      expect(result.value).to be(false)
    end

    it "applies a segment-level progressive rollout for a matching entity" do
      result = handler.feature_evaluation(handler.get_feature("f-seg-progressive"), "e1", email: "john@ibm.com")
      expect(result.enabled).to be(true)
      expect(result.value).to be(true)
    end
  end

  describe "#property_evaluation" do
    it "returns the default value when there is no targeting match" do
      result = handler.property_evaluation(handler.get_property("show-ad"), "e1", {})
      expect(result.value).to be(false)
      expect(result.details.value_type).to eq("DEFAULT_VALUE")
    end

    it "returns the overridden value for a matching segment" do
      result = handler.property_evaluation(handler.get_property("ad-targeted"), "e1", email: "john@ibm.com")
      expect(result.value).to eq("overridden")
      expect(result.details.value_type).to eq("SEGMENT_VALUE")
    end
  end

  describe "#get_rollout_percentage" do
    it "appends the progressive start_at to the entity id for hashing" do
      feature = handler.get_feature("f-progressive")
      percentage, effective_entity_id = handler.get_rollout_percentage(feature, nil, "e1")
      expect(percentage).to eq(100)
      expect(effective_entity_id).to eq("e1#{past_start}")
    end

    it "returns the manual rollout percentage unchanged for the entity id" do
      feature = handler.get_feature("f-enabled")
      percentage, effective_entity_id = handler.get_rollout_percentage(feature, nil, "e1")
      expect(percentage).to eq(100)
      expect(effective_entity_id).to eq("e1")
    end
  end
end
