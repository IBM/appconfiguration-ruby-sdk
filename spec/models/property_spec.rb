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

RSpec.describe IbmAppconfigurationRubySdk::Property do
  let(:property_hash) do
    {
      name: "Show Ad",
      property_id: "show-ad",
      type: "BOOLEAN",
      value: false,
      segment_rules: []
    }
  end

  subject(:property) { described_class.new(property_hash) }

  it "exposes the basic getters" do
    expect(property.name).to eq("Show Ad")
    expect(property.property_id).to eq("show-ad")
    expect(property.type).to eq("BOOLEAN")
    expect(property.value).to be(false)
  end

  it "defaults the data format to TEXT for STRING properties" do
    p = described_class.new(property_hash.merge(type: "STRING", format: nil))
    expect(p.data_format).to eq("TEXT")
  end

  describe "#get_current_value" do
    it "returns nil for a blank entity id" do
      expect(property.get_current_value(nil)).to be_nil
      expect(property.get_current_value("")).to be_nil
    end

    context "when delegating to ConfigurationHandler" do
      let(:handler_double) { instance_double(IbmAppconfigurationRubySdk::ConfigurationHandler) }
      let(:eval_result) do
        IbmAppconfigurationRubySdk::EvaluationResult.new(
          value: "overridden",
          enabled: nil,
          details: IbmAppconfigurationRubySdk::EvaluationDetails.new(value_type: "SEGMENT_VALUE")
        )
      end

      before do
        allow(IbmAppconfigurationRubySdk::ConfigurationHandler).to receive(:instance).and_return(handler_double)
        allow(handler_double).to receive(:property_evaluation).and_return(eval_result)
      end

      it "returns the EvaluationResult from the handler" do
        result = property.get_current_value("user-1", { email: "a@ibm.com" })
        expect(result).to eq(eval_result)
      end

      it "passes self, entity_id, and entity_attributes to the handler" do
        expect(handler_double).to receive(:property_evaluation).with(property, "user-1", { email: "a@ibm.com" })
        property.get_current_value("user-1", { email: "a@ibm.com" })
      end
    end
  end
end
