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

RSpec.describe IbmAppconfigurationRubySdk::Feature do
  let(:feature_hash) do
    {
      name: "Cycle Rentals",
      feature_id: "cycle-rentals",
      type: "BOOLEAN",
      enabled_value: true,
      disabled_value: false,
      enabled: true,
      rollout_percentage: 80,
      segment_rules: []
    }
  end

  subject(:feature) { described_class.new(feature_hash) }

  it "exposes the basic getters" do
    expect(feature.name).to eq("Cycle Rentals")
    expect(feature.feature_id).to eq("cycle-rentals")
    expect(feature.type).to eq("BOOLEAN")
    expect(feature.enabled?).to be(true)
    expect(feature.rollout_percentage).to eq(80)
  end

  it "defaults rollout_type to MANUAL" do
    expect(feature.rollout_type).to eq(IbmAppconfigurationRubySdk::Constants::MANUAL)
  end

  it "defaults rollout_percentage to 100 when not provided" do
    f = described_class.new(feature_hash.reject { |k, _| k == :rollout_percentage })
    expect(f.rollout_percentage).to eq(100)
  end

  it "defaults the data format to TEXT for STRING features" do
    f = described_class.new(feature_hash.merge(type: "STRING", format: nil))
    expect(f.data_format).to eq("TEXT")
  end

  context "with a progressive rollout configuration" do
    let(:progressive_hash) do
      feature_hash.merge(
        rollout_type: IbmAppconfigurationRubySdk::Constants::PROGRESSIVE,
        rollout_configuration: {
          start_at: "2020-01-01T00:00:00Z",
          phases: [{ percentage: 100 }]
        }
      ).reject { |k, _| k == :rollout_percentage }
    end

    subject(:feature) { described_class.new(progressive_hash) }

    it "stores the rollout configuration and leaves rollout_percentage nil" do
      expect(feature.rollout_configuration).not_to be_nil
      expect(feature.rollout_type).to eq(IbmAppconfigurationRubySdk::Constants::PROGRESSIVE)
      expect(feature.rollout_percentage).to be_nil
    end
  end

  describe "#get_current_value" do
    it "returns nil for a blank entity id" do
      expect(feature.get_current_value(nil)).to be_nil
      expect(feature.get_current_value("")).to be_nil
    end

    context "when delegating to ConfigurationHandler" do
      let(:handler_double) { instance_double(IbmAppconfigurationRubySdk::ConfigurationHandler) }
      let(:eval_result) do
        IbmAppconfigurationRubySdk::EvaluationResult.new(
          value: true,
          enabled: true,
          details: IbmAppconfigurationRubySdk::EvaluationDetails.new(value_type: "ENABLED_VALUE")
        )
      end

      before do
        allow(IbmAppconfigurationRubySdk::ConfigurationHandler).to receive(:instance).and_return(handler_double)
        allow(handler_double).to receive(:feature_evaluation).and_return(eval_result)
      end

      it "returns the EvaluationResult from the handler" do
        result = feature.get_current_value("user-1", { role: "admin" })
        expect(result).to eq(eval_result)
      end

      it "passes self, entity_id, and entity_attributes to the handler" do
        expect(handler_double).to receive(:feature_evaluation).with(feature, "user-1", { role: "admin" })
        feature.get_current_value("user-1", { role: "admin" })
      end
    end
  end
end
