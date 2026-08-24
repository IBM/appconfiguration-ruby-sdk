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

RSpec.describe IbmAppconfigurationRubySdk::ConfigFetcher do
  let(:handler_double) { instance_double(IbmAppconfigurationRubySdk::ConfigurationHandler) }
  let(:logger_double)  { instance_double(IbmAppconfigurationRubySdk::Logger, log: nil, info: nil, warning: nil, error: nil) }
  let(:client_double)  { double("BaseService") }

  subject(:fetcher) do
    described_class.new(
      collection_id: "my-col",
      environment_id: "dev",
      handler: handler_double,
      logger: logger_double
    )
  end

  before do
    # Stub all ApiManager interactions so no real HTTP calls are made.
    allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:refresh_token!)
    allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:base_service_client).and_return(client_double)
    allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:headers).and_return({ "Accept" => "application/json" })

    # Stub UrlBuilder
    builder = IbmAppconfigurationRubySdk::UrlBuilder.instance
    builder.guid = "test-guid"
    builder.region = "us-south"
    builder.base_service_url = nil
    builder.use_private_endpoint = false
  end

  # ──────────────────────────────────────────────────────────
  # #fetch
  # ──────────────────────────────────────────────────────────
  describe "#fetch" do
    context "when the API returns 200" do
      before do
        response = double("Response", status: 200, result: { "features" => [] })
        allow(client_double).to receive(:request).and_return(response)
      end

      it "returns ok: true with the data" do
        result = fetcher.fetch
        expect(result[:ok]).to be(true)
        expect(result[:retryable]).to be(false)
        expect(result[:status]).to eq(200)
        expect(result[:data]).to eq({ "features" => [] })
      end
    end

    context "when the API returns an unexpected non-200 status" do
      before do
        response = double("Response", status: 503, result: nil)
        allow(client_double).to receive(:request).and_return(response)
      end

      it "returns ok: false and retryable: true" do
        result = fetcher.fetch
        expect(result[:ok]).to be(false)
        expect(result[:retryable]).to be(true)
        expect(result[:status]).to eq(503)
      end
    end

    context "when IBMCloudSdkCore::ApiException is raised with a known IBM code (404)" do
      before do
        fake_response = double("Response", headers: { "X-Dp-Watson-Tran-Id" => nil, "X-Global-Transaction-Id" => nil })
        allow(client_double).to receive(:request)
          .and_raise(IBMCloudSdkCore::ApiException.new(code: "FTEC1000E", error: "Collection not found", response: fake_response))
      end

      it "returns ok: false, retryable: false, status: 404" do
        result = fetcher.fetch
        expect(result[:ok]).to be(false)
        expect(result[:retryable]).to be(false)
        expect(result[:status]).to eq(404)
      end
    end

    context "when IBMCloudSdkCore::ApiException is raised for rate-limiting (429)" do
      before do
        fake_response = double("Response", headers: { "X-Dp-Watson-Tran-Id" => nil, "X-Global-Transaction-Id" => nil })
        allow(client_double).to receive(:request)
          .and_raise(IBMCloudSdkCore::ApiException.new(code: "FTEC4290E", error: "Too many requests", response: fake_response))
      end

      it "returns ok: false, retryable: true, status: 429" do
        result = fetcher.fetch
        expect(result[:ok]).to be(false)
        expect(result[:retryable]).to be(true)
        expect(result[:status]).to eq(429)
      end
    end

    context "when IBMCloudSdkCore::ApiException is raised for a 5xx error" do
      before do
        fake_response = double("Response", headers: { "X-Dp-Watson-Tran-Id" => nil, "X-Global-Transaction-Id" => nil })
        allow(client_double).to receive(:request)
          .and_raise(IBMCloudSdkCore::ApiException.new(code: "503", error: "Service unavailable", response: fake_response))
      end

      it "returns ok: false, retryable: true" do
        result = fetcher.fetch
        expect(result[:ok]).to be(false)
        expect(result[:retryable]).to be(true)
      end
    end

    context "when a generic StandardError is raised" do
      before do
        allow(client_double).to receive(:request).and_raise(StandardError, "unexpected")
      end

      it "returns ok: false, retryable: true, status: 500" do
        result = fetcher.fetch
        expect(result[:ok]).to be(false)
        expect(result[:retryable]).to be(true)
        expect(result[:status]).to eq(500)
      end
    end
  end

  # ──────────────────────────────────────────────────────────
  # #process_and_load_configurations
  # ──────────────────────────────────────────────────────────
  describe "#process_and_load_configurations" do
    it "returns false when api_response is nil" do
      expect(fetcher.process_and_load_configurations(nil)).to be(false)
    end

    it "calls load_configurations_to_cache with the extracted config and returns true" do
      raw_api_response = {
        "collections" => [{ "collection_id" => "my-col" }],
        "environments" => [
          {
            "environment_id" => "dev",
            "features" => [],
            "properties" => []
          }
        ],
        "segments" => []
      }
      allow(handler_double).to receive(:load_configurations_to_cache)
      result = fetcher.process_and_load_configurations(raw_api_response)
      expect(result).to be(true)
    end

    it "returns false when an exception is raised during processing" do
      allow(fetcher).to receive(:extract_configurations).and_raise(StandardError, "bad data")
      expect(fetcher.process_and_load_configurations({ bad: "data" })).to be(false)
    end
  end

  # ──────────────────────────────────────────────────────────
  # #load_configurations_to_cache
  # ──────────────────────────────────────────────────────────
  describe "#load_configurations_to_cache" do
    it "returns false when data is nil" do
      expect(fetcher.load_configurations_to_cache(nil)).to be(false)
    end

    it "delegates to the handler and returns true" do
      data = { features: [], properties: [], segments: [] }
      expect(handler_double).to receive(:load_configurations_to_cache).with(data)
      expect(fetcher.load_configurations_to_cache(data)).to be(true)
    end

    it "returns false when the handler raises" do
      allow(handler_double).to receive(:load_configurations_to_cache).and_raise(StandardError, "fail")
      expect(fetcher.load_configurations_to_cache({ features: [] })).to be(false)
    end
  end
end
