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

RSpec.describe IbmAppconfigurationRubySdk::UrlBuilder do
  subject(:builder) { described_class.instance }

  # Reset to a known baseline before every example.
  before do
    builder.region = "us-south"
    builder.guid   = "test-guid"
    builder.apikey = "test-apikey-1234"
    builder.use_private_endpoint = false
    builder.base_service_url = nil   # clear any override
  end

  # ──────────────────────────────────────────────────────────
  # base_service_url
  # ──────────────────────────────────────────────────────────
  describe "#base_service_url" do
    context "public production endpoint (no override)" do
      it "returns https://<region>.apprapp.cloud.ibm.com" do
        expect(builder.base_service_url).to eq("https://us-south.apprapp.cloud.ibm.com")
      end
    end

    context "private production endpoint" do
      before { builder.use_private_endpoint = true }

      it "prepends 'private.' to the region host" do
        expect(builder.base_service_url).to eq("https://private.us-south.apprapp.cloud.ibm.com")
      end
    end

    context "with an override URL" do
      before { builder.base_service_url = "https://dev.example.com" }

      it "returns the override URL as-is when private endpoint is disabled" do
        expect(builder.base_service_url).to eq("https://dev.example.com")
      end

      it "prepends 'private.' after the scheme when private endpoint is enabled" do
        builder.use_private_endpoint = true
        expect(builder.base_service_url).to eq("https://private.dev.example.com")
      end
    end
  end

  # ──────────────────────────────────────────────────────────
  # iam_url
  # ──────────────────────────────────────────────────────────
  describe "#iam_url" do
    context "no override URL (production)" do
      it "returns the production IAM URL" do
        expect(builder.iam_url).to eq("https://iam.cloud.ibm.com/identity/token")
      end

      it "prepends 'private.' when private endpoint is enabled" do
        builder.use_private_endpoint = true
        expect(builder.iam_url).to eq("https://private.iam.cloud.ibm.com/identity/token")
      end
    end

    context "with override URL (dev/stage)" do
      before { builder.base_service_url = "https://dev.example.com" }

      it "returns the test IAM URL" do
        expect(builder.iam_url).to eq("https://iam.test.cloud.ibm.com/identity/token")
      end

      it "prepends 'private.' to the test IAM host when private endpoint is enabled" do
        builder.use_private_endpoint = true
        expect(builder.iam_url).to eq("https://private.iam.test.cloud.ibm.com/identity/token")
      end
    end
  end

  # ──────────────────────────────────────────────────────────
  # set_websocket_url / websocket_url
  # ──────────────────────────────────────────────────────────
  describe "#websocket_url" do
    it "returns nil before set_websocket_url is called" do
      # Reset by clearing via a fresh region assignment (builder already reset in before block,
      # but websocket_url may carry a value from a previous test — reset explicitly).
      builder.instance_variable_set(:@websocket_full_url, nil)
      expect(builder.websocket_url).to be_nil
    end
  end

  describe "#set_websocket_url" do
    it "builds the correct WSS URL with collection and environment query params" do
      builder.set_websocket_url("my-collection", "prod-env")
      expect(builder.websocket_url).to eq(
        "wss://us-south.apprapp.cloud.ibm.com/apprapp/wsfeature?" \
        "instance_id=test-guid&collection_id=my-collection&environment_id=prod-env"
      )
    end

    it "uses the override URL when set" do
      builder.base_service_url = "https://dev.example.com"
      builder.set_websocket_url("col", "env")
      expect(builder.websocket_url).to include("wss://dev.example.com")
    end

    it "includes 'private.' in WSS URL when private endpoint is enabled" do
      builder.use_private_endpoint = true
      builder.set_websocket_url("col", "env")
      expect(builder.websocket_url).to include("wss://private.us-south")
    end
  end

  # ──────────────────────────────────────────────────────────
  # use_private_endpoint?
  # ──────────────────────────────────────────────────────────
  describe "#use_private_endpoint?" do
    it "returns false by default" do
      expect(builder.use_private_endpoint?).to be(false)
    end

    it "returns true after the writer is set to true" do
      builder.use_private_endpoint = true
      expect(builder.use_private_endpoint?).to be(true)
    end
  end

  # ──────────────────────────────────────────────────────────
  # inspect
  # ──────────────────────────────────────────────────────────
  describe "#inspect" do
    it "shows the region" do
      expect(builder.inspect).to include("region=")
    end

    it "masks all but the first 4 characters of the API key" do
      # API key is "test-apikey-1234" (16 chars), first 4 = "test"
      expect(builder.inspect).to include("test")
      expect(builder.inspect).not_to include("test-apikey-1234")
    end

    it "shows 'nil' when no apikey is set" do
      builder.apikey = nil
      expect(builder.inspect).to include("nil")
    end
  end

  # ──────────────────────────────────────────────────────────
  # guid getter / setter
  # ──────────────────────────────────────────────────────────
  describe "#guid" do
    it "returns the value set via the writer" do
      builder.guid = "my-guid"
      expect(builder.guid).to eq("my-guid")
    end
  end

  # ──────────────────────────────────────────────────────────
  # set_base_service_url alias
  # ──────────────────────────────────────────────────────────
  describe "#set_base_service_url" do
    it "is an alias for base_service_url=" do
      builder.set_base_service_url("https://alias.example.com")
      expect(builder.base_service_url).to eq("https://alias.example.com")
    end
  end
end
