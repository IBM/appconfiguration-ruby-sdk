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

RSpec.describe "configuration utils" do
  include IbmAppconfigurationRubySdk::Utils
  describe "#compute_hash" do
    it "is deterministic for the same input" do
      expect(compute_hash("entity:feature")).to eq(compute_hash("entity:feature"))
    end

    it "produces different hashes for different inputs" do
      expect(compute_hash("a")).not_to eq(compute_hash("b"))
    end
  end

  describe "#get_normalized_value" do
    it "returns a value in the range 0..100" do
      value = get_normalized_value("some-entity:some-feature")
      expect(value).to be >= 0
      expect(value).to be <= 100
    end

    it "is deterministic" do
      expect(get_normalized_value("x:y")).to eq(get_normalized_value("x:y"))
    end
  end

  describe "#validate_resource" do
    it "returns true when the resource has no collections key" do
      expect(validate_resource({ feature_id: "f1" }, "c1")).to be(true)
    end

    it "returns true when the resource belongs to the collection" do
      resource = { feature_id: "f1", collections: [{ collection_id: "c1" }, { collection_id: "c2" }] }
      expect(validate_resource(resource, "c2")).to be(true)
    end

    it "returns false when the resource does not belong to the collection" do
      resource = { feature_id: "f1", collections: [{ collection_id: "c1" }] }
      expect(validate_resource(resource, "c9")).to be(false)
    end
  end

  describe "#symbolize_keys" do
    it "recursively converts string keys to symbols" do
      input = { "a" => 1, "b" => { "c" => [{ "d" => 2 }] } }
      expect(symbolize_keys(input)).to eq(a: 1, b: { c: [{ d: 2 }] })
    end
  end

  describe "#parse_rollout_configuration_phases" do
    it "raises when the configuration is invalid" do
      expect { parse_rollout_configuration_phases({}) }.to raise_error(ArgumentError)
      expect { parse_rollout_configuration_phases(nil) }.to raise_error(ArgumentError)
    end

    it "builds a sorted timestamp -> percentage map with an initial zero entry" do
      config = {
        start_at: "2020-01-01T00:00:00Z",
        phases: [
          { percentage: 25, duration: 1, duration_type: "hours" },
          { percentage: 50, duration: 1, duration_type: "hours" },
          { percentage: 100 }
        ]
      }

      result = parse_rollout_configuration_phases(config)
      start_ms = Time.parse("2020-01-01T00:00:00Z").to_i * 1000

      expect(result[0]).to eq(0)
      expect(result[start_ms]).to eq(25)
      expect(result[start_ms + (3_600_000 * 1)]).to eq(50)
      expect(result[start_ms + (3_600_000 * 2)]).to eq(100)
      # Keys must be sorted ascending.
      expect(result.keys).to eq(result.keys.sort)
    end
  end

  describe "#get_current_rollout_percentage" do
    it "returns 0 for nil or empty maps" do
      expect(get_current_rollout_percentage(nil)).to eq(0)
      expect(get_current_rollout_percentage({})).to eq(0)
    end

    it "returns the percentage of the most recent past phase" do
      now_ms = (Time.now.to_f * 1000).to_i
      rollout_map = {
        0 => 0,
        now_ms - 20_000 => 40,
        now_ms - 10_000 => 70,
        now_ms + 10_000 => 100
      }
      expect(get_current_rollout_percentage(rollout_map)).to eq(70)
    end

    it "returns 0 when the rollout has not started yet" do
      now_ms = (Time.now.to_f * 1000).to_i
      rollout_map = { 0 => 0, now_ms + 60_000 => 100 }
      expect(get_current_rollout_percentage(rollout_map)).to eq(0)
    end
  end

  describe "#extract_configurations" do
    let(:configurations) do
      {
        collections: [{ collection_id: "c1", name: "C1" }],
        environments: [
          {
            environment_id: "dev",
            features: [
              { name: "F1", feature_id: "f1", type: "BOOLEAN", enabled_value: true,
                disabled_value: false, enabled: true, rollout_percentage: 100, segment_rules: [] }
            ],
            properties: [
              { name: "P1", property_id: "p1", type: "BOOLEAN", value: false, segment_rules: [] }
            ]
          }
        ],
        segments: []
      }
    end

    it "extracts features, properties and segments for a matching environment/collection" do
      result = extract_configurations(configurations, "dev", "c1")
      expect(result[:features].length).to eq(1)
      expect(result[:properties].length).to eq(1)
      expect(result[:segments]).to eq([])
    end

    it "raises when the collection is not found" do
      expect { extract_configurations(configurations, "dev", "unknown") }
        .to raise_error(/Required collection not found in collections/)
    end

    it "raises when the environment is not found" do
      expect { extract_configurations(configurations, "prod", "c1") }
        .to raise_error(/Matching environment not found in configuration/)
    end
  end

  describe "#append_segment_id" do
    it "collects segment IDs from segment_rules into the provided set" do
      resource = {
        segment_rules: [
          { rules: [{ segments: %w[seg-a seg-b] }] },
          { rules: [{ segments: ["seg-c"] }] }
        ]
      }
      ids = Set.new
      append_segment_id(resource, ids)
      expect(ids).to contain_exactly("seg-a", "seg-b", "seg-c")
    end

    it "is a no-op when segment_rules is nil" do
      ids = Set.new
      append_segment_id({}, ids)
      expect(ids).to be_empty
    end

    it "does not add duplicates to the set" do
      resource = {
        segment_rules: [
          { rules: [{ segments: ["seg-a"] }] },
          { rules: [{ segments: ["seg-a"] }] }
        ]
      }
      ids = Set.new
      append_segment_id(resource, ids)
      expect(ids.size).to eq(1)
    end
  end

  describe "#extract_environment_data" do
    let(:data) do
      {
        segments: [{ segment_id: "s1", name: "S1", rules: [] }],
        environments: [
          {
            environment_id: "dev",
            features: [{ feature_id: "f1" }],
            properties: [{ property_id: "p1" }]
          }
        ]
      }
    end

    it "returns features, properties and segments for a matching environment_id" do
      result = extract_environment_data(data, "dev")
      expect(result[:features]).to eq([{ feature_id: "f1" }])
      expect(result[:properties]).to eq([{ property_id: "p1" }])
      expect(result[:segments]).to eq(data[:segments])
    end

    it "raises when the environment is not found" do
      expect { extract_environment_data(data, "prod") }
        .to raise_error(IbmAppconfigurationRubySdk::Error, /Matching environment not found/)
    end

    it "raises when the data structure is invalid" do
      expect { extract_environment_data({}, "dev") }
        .to raise_error(IbmAppconfigurationRubySdk::Error, /Improper Data format/)
    end

    it "defaults missing features to an empty array" do
      data_no_features = {
        segments: [],
        environments: [{ environment_id: "dev", properties: [] }]
      }
      result = extract_environment_data(data_no_features, "dev")
      expect(result[:features]).to eq([])
    end
  end

  describe "#extract_resources" do
    let(:resource_data) do
      {
        features: [
          { feature_id: "f1", collections: [{ collection_id: "c1" }] },
          { feature_id: "f2", collections: [{ collection_id: "c2" }] }
        ],
        properties: [
          { property_id: "p1", collections: [{ collection_id: "c1" }] }
        ],
        segments: []
      }
    end

    it "returns only features and properties belonging to the given collection" do
      result = extract_resources(resource_data, "c1")
      expect(result[:features].map { |f| f[:feature_id] }).to eq(["f1"])
      expect(result[:properties].map { |p| p[:property_id] }).to eq(["p1"])
    end

    it "returns empty arrays when nothing matches the collection" do
      result = extract_resources(resource_data, "c9")
      expect(result[:features]).to be_empty
      expect(result[:properties]).to be_empty
    end

    it "raises when a referenced segment is absent from the segments list" do
      data_with_missing_seg = {
        features: [{
          feature_id: "f1",
          collections: [{ collection_id: "c1" }],
          segment_rules: [{ rules: [{ segments: ["missing-seg"] }] }]
        }],
        properties: [],
        segments: []
      }
      expect { extract_resources(data_with_missing_seg, "c1") }
        .to raise_error(IbmAppconfigurationRubySdk::Error, /Required segment doesn't exist/)
    end
  end
end
