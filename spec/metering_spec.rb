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

RSpec.describe IbmAppconfigurationRubySdk::Metering do
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
        metering.add_metering("g1", "dev", "c1", "e1", IbmAppconfigurationRubySdk::Constants::DEFAULT_SEGMENT_ID, "feature-1", nil)
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
      metering.add_metering("g1", "dev", "c1", "e1", IbmAppconfigurationRubySdk::Constants::DEFAULT_SEGMENT_ID, "feature-1", nil)
      metering.add_metering("g1", "dev", "c1", "e1", IbmAppconfigurationRubySdk::Constants::DEFAULT_SEGMENT_ID, nil, "property-1")

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
      expect(IbmAppconfigurationRubySdk::Constants::DEFAULT_USAGE_LIMIT).to eq(30)
    end
  end

  describe "#send_to_server — server-down retry behaviour" do
    let(:data) { { "collection_id" => "c1", "environment_id" => "dev", "usages" => [] } }

    before do
      metering.set_metering_url("https://example.com/metering", "test-key")
      # Stub backoff helpers to return tiny delays so specs complete fast
      allow(metering).to receive(:metering_compute_cap_delay_ms).and_return(10_000)
      allow(metering).to receive(:metering_compute_next_delay_ms).and_return(10) # 10 ms
    end

    after do
      metering.set_metering_url(nil, nil)
    end

    it "retries when the server is down (connection error, nil status) and stays alive" do
      call_count = 0
      fake_response = double("response", status: 202)

      allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:post_metering) do
        call_count += 1
        raise StandardError.new("connection refused") if call_count < 3

        fake_response
      end

      metering.send_to_server(data)

      # Allow enough time for the two retry threads to complete
      sleep(0.2)

      expect(call_count).to eq(3)
    end

    it "keeps two independent payloads retrying concurrently when the server is down" do
      data_b = { "collection_id" => "c2", "environment_id" => "dev", "usages" => [] }
      calls_a = 0
      calls_b = 0

      allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:post_metering) do |_url, payload, _key|
        fake_response = double("response", status: 202)
        if payload["collection_id"] == "c1"
          calls_a += 1
          raise StandardError.new("server down") if calls_a < 2
        else
          calls_b += 1
          raise StandardError.new("server down") if calls_b < 2
        end
        fake_response
      end

      metering.send_to_server(data)
      metering.send_to_server(data_b)

      sleep(0.2)

      # Both payloads must have retried and eventually succeeded
      expect(calls_a).to eq(2)
      expect(calls_b).to eq(2)
    end

    it "does not retry on a non-retryable 4xx error" do
      call_count = 0
      api_err = StandardError.new("bad request")
      allow(api_err).to receive(:status).and_return(400)

      allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:post_metering) do
        call_count += 1
        raise api_err
      end

      metering.send_to_server(data)
      sleep(0.1)

      expect(call_count).to eq(1)
    end

    it "logs success with SUCCESSFULLY_POSTED_METERING_DATA constant when 202 is returned" do
      fake_response = double("response", status: 202)
      allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:post_metering).and_return(fake_response)

      logger_double = instance_double(IbmAppconfigurationRubySdk::Logger)
      allow(logger_double).to receive(:info)
      allow(metering).to receive(:instance_variable_get).with(:@logger).and_return(logger_double)
      metering.instance_variable_set(:@logger, logger_double)

      metering.send_to_server(data)

      expect(logger_double).to have_received(:info)
        .with(IbmAppconfigurationRubySdk::Constants::SUCCESSFULLY_POSTED_METERING_DATA)
    end
  end
end
