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

RSpec.describe IbmAppconfigurationRubySdk::ApiManager do
  # Reset all cached state before every test.
  before do
    described_class.reset!
    # Point UrlBuilder at known dummy values so tests don't depend on env.
    builder = IbmAppconfigurationRubySdk::UrlBuilder.instance
    builder.region = "us-south"
    builder.guid   = "test-guid"
    builder.apikey = "test-apikey"
    builder.use_private_endpoint = false
    builder.base_service_url = nil
  end

  after { described_class.reset! }

  # ──────────────────────────────────────────────────────────
  # .headers
  # ──────────────────────────────────────────────────────────
  describe ".headers" do
    it "returns Accept and User-Agent for a GET request" do
      h = described_class.headers
      expect(h["Accept"]).to eq("application/json")
      expect(h["User-Agent"]).to include("appconfiguration-ruby-sdk/")
      expect(h.key?("Content-Type")).to be(false)
    end

    it "adds Content-Type for a POST request" do
      h = described_class.headers(is_post: true)
      expect(h["Content-Type"]).to eq("application/json")
    end
  end

  # ──────────────────────────────────────────────────────────
  # .set_authenticator
  # ──────────────────────────────────────────────────────────
  describe ".set_authenticator" do
    let(:mock_authenticator) { double("IamAuthenticator") }

    it "stores the IAM authenticator on success" do
      allow(IBMCloudSdkCore::IamAuthenticator).to receive(:new).and_return(mock_authenticator)
      described_class.set_authenticator
      expect(described_class.iam_authenticator).to eq(mock_authenticator)
    end

    it "passes the apikey to the authenticator constructor" do
      expect(IBMCloudSdkCore::IamAuthenticator)
        .to receive(:new).with(hash_including(apikey: "test-apikey"))
        .and_return(mock_authenticator)
      described_class.set_authenticator
    end

    it "does NOT include the :url key when using the default production IAM URL" do
      expect(IBMCloudSdkCore::IamAuthenticator)
        .to receive(:new) do |opts|
          expect(opts.key?(:url)).to be(false)
          mock_authenticator
        end
      described_class.set_authenticator
    end

    it "includes :url when using a custom (non-production) IAM URL" do
      IbmAppconfigurationRubySdk::UrlBuilder.instance.base_service_url = "https://dev.example.com"
      expect(IBMCloudSdkCore::IamAuthenticator)
        .to receive(:new).with(hash_including(url: anything))
        .and_return(mock_authenticator)
      described_class.set_authenticator
    end

    it "re-raises IBMCloudSdkCore::ApiException as an APIError" do
      fake_response = double("Response", headers: { "X-Dp-Watson-Tran-Id" => nil, "X-Global-Transaction-Id" => nil })
      api_exc = IBMCloudSdkCore::ApiException.new(code: "401", error: "Unauthorized", response: fake_response)
      allow(IBMCloudSdkCore::IamAuthenticator).to receive(:new).and_raise(api_exc)
      expect { described_class.set_authenticator }
        .to raise_error(IbmAppconfigurationRubySdk::APIError)
    end

    it "re-raises a generic StandardError as ConfigurationError" do
      allow(IBMCloudSdkCore::IamAuthenticator).to receive(:new)
        .and_raise(StandardError, "socket error")
      expect { described_class.set_authenticator }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError)
    end
  end

  # ──────────────────────────────────────────────────────────
  # .base_service_client
  # ──────────────────────────────────────────────────────────
  describe ".base_service_client" do
    it "raises ConfigurationError when no authenticator has been set" do
      expect { described_class.base_service_client }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError, /Authenticator not set/)
    end

    it "creates and memoizes a BaseService after set_authenticator is called" do
      mock_auth   = double("IamAuthenticator")
      mock_client = double("BaseService")
      allow(IBMCloudSdkCore::IamAuthenticator).to receive(:new).and_return(mock_auth)
      allow(IBMCloudSdkCore::BaseService).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:configure_http_client)

      described_class.set_authenticator
      client = described_class.base_service_client
      expect(client).to eq(mock_client)

      # Second call returns same instance (memoized).
      expect(IBMCloudSdkCore::BaseService).not_to receive(:new)
      expect(described_class.base_service_client).to eq(mock_client)
    end
  end

  # ──────────────────────────────────────────────────────────
  # .refresh_token!
  # ──────────────────────────────────────────────────────────
  describe ".refresh_token!" do
    it "raises ConfigurationError when no authenticator has been set" do
      expect { described_class.refresh_token! }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError, /Authenticator not set/)
    end

    it "recreates the IamAuthenticator (calls set_authenticator) to force a fresh token" do
      mock_auth = double("IamAuthenticator")
      # IamAuthenticator.new is called once by set_authenticator, then again by refresh_token!
      expect(IBMCloudSdkCore::IamAuthenticator).to receive(:new).twice.and_return(mock_auth)
      described_class.set_authenticator
      described_class.refresh_token!
    end
  end

  # ──────────────────────────────────────────────────────────
  # .token
  # ──────────────────────────────────────────────────────────
  describe ".token" do
    it "raises ConfigurationError when no authenticator has been set" do
      expect { described_class.token }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError, /Authenticator not set/)
    end

    it "returns the Authorization header value set by authenticate" do
      mock_auth = double("IamAuthenticator")
      allow(IBMCloudSdkCore::IamAuthenticator).to receive(:new).and_return(mock_auth)
      allow(mock_auth).to receive(:authenticate) do |req|
        req["Authorization"] = "Bearer fake-token"
      end
      described_class.set_authenticator
      expect(described_class.token).to eq("Bearer fake-token")
    end

    it "raises ConfigurationError when authenticate does not set Authorization" do
      mock_auth = double("IamAuthenticator")
      allow(IBMCloudSdkCore::IamAuthenticator).to receive(:new).and_return(mock_auth)
      allow(mock_auth).to receive(:authenticate) # does nothing — Authorization never set
      described_class.set_authenticator
      expect { described_class.token }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError, /no Authorization header/)
    end
  end

  # ──────────────────────────────────────────────────────────
  # .post_metering
  # ──────────────────────────────────────────────────────────
  describe ".post_metering" do
    let(:mock_auth)   { double("IamAuthenticator") }
    let(:mock_client) { double("BaseService") }

    before do
      # IamAuthenticator.new is called by set_authenticator AND by refresh_token! inside post_metering
      allow(IBMCloudSdkCore::IamAuthenticator).to receive(:new).and_return(mock_auth)
      allow(mock_auth).to receive(:authenticate)
      allow(IBMCloudSdkCore::BaseService).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:configure_http_client)
      described_class.set_authenticator
    end

    it "calls client.request with POST method, path, and json payload" do
      payload = { "usages" => [] }
      url = "https://us-south.apprapp.cloud.ibm.com/apprapp/metering/v1/instances/guid/usage"

      expect(mock_client).to receive(:request).with(
        method: "POST",
        url: "/apprapp/metering/v1/instances/guid/usage",
        headers: hash_including("Content-Type" => "application/json"),
        json: payload
      )
      described_class.post_metering(url, payload, "apikey")
    end
  end

  # ──────────────────────────────────────────────────────────
  # .reset!
  # ──────────────────────────────────────────────────────────
  describe ".reset!" do
    it "clears the cached authenticator" do
      mock_auth = double("IamAuthenticator")
      allow(IBMCloudSdkCore::IamAuthenticator).to receive(:new).and_return(mock_auth)
      described_class.set_authenticator
      expect(described_class.iam_authenticator).not_to be_nil
      described_class.reset!
      expect(described_class.iam_authenticator).to be_nil
    end
  end

  # ──────────────────────────────────────────────────────────
  # .inspect
  # ──────────────────────────────────────────────────────────
  describe ".inspect" do
    it "does not include raw credentials" do
      expect(described_class.inspect).not_to include("test-apikey")
    end

    it "shows authenticated=false when no authenticator has been set" do
      expect(described_class.inspect).to include("authenticated=false")
    end

    it "shows authenticated=true after set_authenticator is called" do
      mock_auth = double("IamAuthenticator")
      allow(IBMCloudSdkCore::IamAuthenticator).to receive(:new).and_return(mock_auth)
      described_class.set_authenticator
      expect(described_class.inspect).to include("authenticated=true")
    end
  end
end
