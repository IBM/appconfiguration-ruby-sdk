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

RSpec.describe Metering do
  subject(:metering) { described_class.instance }

  before do
    # Clear any accumulated metering data (URL is unset, so nothing is posted).
    metering.set_metering_url(nil, nil)
    metering.send_metering
  end

  describe "#build_composite_key / #parse_composite_key" do
    it "round-trips the components" do
      key = metering.build_composite_key("guid", "env", "coll", "feat", "entity", "seg")
      expect(metering.parse_composite_key(key)).to eq(%w[guid env coll feat entity seg])
    end

    it "converts nil components to empty strings" do
      key = metering.build_composite_key("guid", "env", "coll", nil, "entity", nil)
      expect(metering.parse_composite_key(key)).to eq(["guid", "env", "coll", "", "entity", ""])
    end
  end

  describe "#add_metering and #send_metering" do
    it "aggregates repeated evaluations of the same key into a single usage with a count" do
      3.times do
        metering.add_metering("g1", "dev", "c1", "e1", Constants::DEFAULT_SEGMENT_ID, "feature-1", nil)
      end

      result = metering.send_metering
      usages = result["g1"].first["usages"]
      expect(usages.length).to eq(1)
      expect(usages.first["feature_id"]).to eq("feature-1")
      expect(usages.first["count"]).to eq(3)
      # DEFAULT_SEGMENT_ID and DEFAULT_ENTITY_ID are normalized to nil in the payload.
      expect(usages.first["segment_id"]).to be_nil
    end

    it "separates feature and property usages" do
      metering.add_metering("g1", "dev", "c1", "e1", Constants::DEFAULT_SEGMENT_ID, "feature-1", nil)
      metering.add_metering("g1", "dev", "c1", "e1", Constants::DEFAULT_SEGMENT_ID, nil, "property-1")

      result = metering.send_metering
      usages = result["g1"].first["usages"]
      expect(usages.map { |u| u["feature_id"] || u["property_id"] }).to contain_exactly("feature-1", "property-1")
    end

    it "returns an empty hash when there is nothing to send" do
      expect(metering.send_metering).to eq({})
    end
  end

  describe "usage limit constant" do
    it "matches the Go SDK default of 30" do
      expect(Constants::DEFAULT_USAGE_LIMIT).to eq(30)
    end
  end
end
