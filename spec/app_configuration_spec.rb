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

RSpec.describe IbmAppconfigurationRubySdk::AppConfiguration do
  subject(:app_config) { described_class.instance }

  let(:handler_double) do
    instance_double(
      IbmAppconfigurationRubySdk::ConfigurationHandler,
      init: nil,
      set_context: nil,
      get_feature: nil,
      get_features: {},
      get_property: nil,
      get_properties: {},
      get_secret: nil,
      track: nil,
      connected?: false,
      register_configuration_update_listener: nil
    )
  end

  # Reset singleton state before every test so tests are independent.
  before do
    app_config.instance_variable_set(:@initialized, false)
    app_config.instance_variable_set(:@context_initialized, false)
    app_config.instance_variable_set(:@configuration_handler, nil)
    app_config.instance_variable_set(:@use_private_endpoint, false)
    # Silently redirect any handler calls to our double by default.
    allow(IbmAppconfigurationRubySdk::ConfigurationHandler)
      .to receive(:instance).and_return(handler_double)
  end

  # ──────────────────────────────────────────────────────────
  # Region constants
  # ──────────────────────────────────────────────────────────
  describe "region constants" do
    it "defines REGION_US_SOUTH" do
      expect(described_class::REGION_US_SOUTH).to eq("us-south")
    end

    it "defines REGION_EU_GB" do
      expect(described_class::REGION_EU_GB).to eq("eu-gb")
    end

    it "defines REGION_AU_SYD" do
      expect(described_class::REGION_AU_SYD).to eq("au-syd")
    end

    it "defines REGION_US_EAST" do
      expect(described_class::REGION_US_EAST).to eq("us-east")
    end

    it "defines REGION_EU_DE" do
      expect(described_class::REGION_EU_DE).to eq("eu-de")
    end

    it "defines REGION_CA_TOR" do
      expect(described_class::REGION_CA_TOR).to eq("ca-tor")
    end

    it "defines REGION_JP_TOK" do
      expect(described_class::REGION_JP_TOK).to eq("jp-tok")
    end

    it "defines REGION_JP_OSA" do
      expect(described_class::REGION_JP_OSA).to eq("jp-osa")
    end
  end

  # ──────────────────────────────────────────────────────────
  # .configure / .configuration
  # ──────────────────────────────────────────────────────────
  describe ".configure" do
    it "yields a Configuration object" do
      yielded = nil
      described_class.configure { |c| yielded = c }
      expect(yielded).to be_a(IbmAppconfigurationRubySdk::Configuration)
    end

    it "returns the same Configuration object on subsequent calls" do
      c1 = described_class.configuration
      c2 = described_class.configuration
      expect(c1).to equal(c2)
    end
  end

  # ──────────────────────────────────────────────────────────
  # .override_service_url
  # ──────────────────────────────────────────────────────────
  describe ".override_service_url" do
    it "delegates to UrlBuilder#set_base_service_url" do
      builder = IbmAppconfigurationRubySdk::UrlBuilder.instance
      expect(builder).to receive(:set_base_service_url).with("https://custom.example.com")
      described_class.override_service_url("https://custom.example.com")
    end

    it "does nothing when url is nil" do
      builder = IbmAppconfigurationRubySdk::UrlBuilder.instance
      expect(builder).not_to receive(:set_base_service_url)
      described_class.override_service_url(nil)
    end
  end

  # ──────────────────────────────────────────────────────────
  # #init
  # ──────────────────────────────────────────────────────────
  describe "#init" do
    it "raises ConfigurationError when region is nil" do
      expect { app_config.init(region: nil, guid: "g", apikey: "k") }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError)
    end

    it "raises ConfigurationError when guid is nil" do
      expect { app_config.init(region: "us-south", guid: nil, apikey: "k") }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError)
    end

    it "raises ConfigurationError when apikey is nil" do
      expect { app_config.init(region: "us-south", guid: "g", apikey: nil) }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError)
    end

    it "calls ConfigurationHandler#init with all params on success" do
      expect(handler_double).to receive(:init).with(
        region: "us-south", guid: "g", apikey: "k", use_private_endpoint: false
      )
      app_config.init(region: "us-south", guid: "g", apikey: "k")
    end

    it "sets @initialized to true on success" do
      app_config.init(region: "us-south", guid: "g", apikey: "k")
      expect(app_config.instance_variable_get(:@initialized)).to be(true)
    end

    it "is idempotent — calling twice only calls handler once" do
      expect(handler_double).to receive(:init).once
      app_config.init(region: "us-south", guid: "g", apikey: "k")
      app_config.init(region: "us-south", guid: "g", apikey: "k")
    end
  end

  # ──────────────────────────────────────────────────────────
  # #set_context
  # ──────────────────────────────────────────────────────────
  describe "#set_context" do
    before { app_config.init(region: "us-south", guid: "g", apikey: "k") }

    it "raises ConfigurationError when called before init" do
      app_config.instance_variable_set(:@initialized, false)
      expect { app_config.set_context("col", "env") }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError)
    end

    it "raises ConfigurationError when collection_id is nil" do
      expect { app_config.set_context(nil, "env") }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError)
    end

    it "raises ConfigurationError when environment_id is nil" do
      expect { app_config.set_context("col", nil) }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError)
    end

    it "raises when live_config_update_enabled: false with no bootstrap_file" do
      expect { app_config.set_context("col", "env", live_config_update_enabled: false) }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError)
    end

    it "raises when bootstrap_file has the wrong extension" do
      expect { app_config.set_context("col", "env", bootstrap_file: "/path/to/file.txt") }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError)
    end

    it "raises when live_config_update_enabled is not a boolean" do
      expect { app_config.set_context("col", "env", live_config_update_enabled: "yes") }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError)
    end

    it "raises when persistent_cache_directory is not a non-empty string" do
      expect { app_config.set_context("col", "env", persistent_cache_directory: 123) }
        .to raise_error(IbmAppconfigurationRubySdk::ConfigurationError)
    end

    it "delegates to handler with valid args and sets @context_initialized" do
      expect(handler_double).to receive(:set_context).with("col", "env", anything)
      app_config.set_context("col", "env")
      expect(app_config.instance_variable_get(:@context_initialized)).to be(true)
    end

    it "is idempotent — calling twice only calls handler once" do
      expect(handler_double).to receive(:set_context).once
      app_config.set_context("col", "env")
      app_config.set_context("col", "env")
    end
  end

  # ──────────────────────────────────────────────────────────
  # #get_feature / #get_features
  # ──────────────────────────────────────────────────────────
  describe "#get_feature" do
    it "returns nil and logs when not initialized" do
      expect(app_config.get_feature("f1")).to be_nil
    end

    it "delegates to handler when fully initialized" do
      app_config.init(region: "r", guid: "g", apikey: "k")
      app_config.instance_variable_set(:@context_initialized, true)
      feature_double = instance_double(IbmAppconfigurationRubySdk::Feature)
      allow(handler_double).to receive(:get_feature).with("f1").and_return(feature_double)
      expect(app_config.get_feature("f1")).to eq(feature_double)
    end
  end

  describe "#get_features" do
    it "returns nil when not initialized" do
      expect(app_config.get_features).to be_nil
    end

    it "delegates to handler when fully initialized" do
      app_config.init(region: "r", guid: "g", apikey: "k")
      app_config.instance_variable_set(:@context_initialized, true)
      allow(handler_double).to receive(:get_features).and_return({ "f1" => double })
      expect(app_config.get_features).to be_a(Hash)
    end
  end

  # ──────────────────────────────────────────────────────────
  # #get_property / #get_properties
  # ──────────────────────────────────────────────────────────
  describe "#get_property" do
    it "returns nil when not initialized" do
      expect(app_config.get_property("p1")).to be_nil
    end

    it "delegates to handler when fully initialized" do
      app_config.init(region: "r", guid: "g", apikey: "k")
      app_config.instance_variable_set(:@context_initialized, true)
      prop_double = instance_double(IbmAppconfigurationRubySdk::Property)
      allow(handler_double).to receive(:get_property).with("p1").and_return(prop_double)
      expect(app_config.get_property("p1")).to eq(prop_double)
    end
  end

  describe "#get_properties" do
    it "returns nil when not initialized" do
      expect(app_config.get_properties).to be_nil
    end
  end

  # ──────────────────────────────────────────────────────────
  # #get_secret
  # ──────────────────────────────────────────────────────────
  describe "#get_secret" do
    let(:sm_double) { double("SecretsManager") }

    it "returns nil and logs when not initialized" do
      expect(app_config.get_secret("p1", sm_double)).to be_nil
    end

    it "returns nil when secrets_manager_service is nil even if initialized" do
      app_config.init(region: "r", guid: "g", apikey: "k")
      app_config.instance_variable_set(:@context_initialized, true)
      expect(app_config.get_secret("p1", nil)).to be_nil
    end

    it "delegates to handler when fully initialized and secrets_manager is provided" do
      app_config.init(region: "r", guid: "g", apikey: "k")
      app_config.instance_variable_set(:@context_initialized, true)
      secret_double = instance_double(IbmAppconfigurationRubySdk::SecretProperty)
      allow(handler_double).to receive(:get_secret).and_return(secret_double)
      expect(app_config.get_secret("p1", sm_double)).to eq(secret_double)
    end
  end

  # ──────────────────────────────────────────────────────────
  # #connected?
  # ──────────────────────────────────────────────────────────
  describe "#connected?" do
    it "returns false before initialization" do
      expect(app_config.connected?).to be(false)
    end

    it "delegates to handler when fully initialized" do
      app_config.init(region: "r", guid: "g", apikey: "k")
      app_config.instance_variable_set(:@context_initialized, true)
      allow(handler_double).to receive(:connected?).and_return(true)
      expect(app_config.connected?).to be(true)
    end
  end

  # ──────────────────────────────────────────────────────────
  # #set_debug
  # ──────────────────────────────────────────────────────────
  describe "#set_debug" do
    after { IbmAppconfigurationRubySdk::Logger.instance.debug = false }

    it "sets the logger debug flag to true" do
      app_config.set_debug(true)
      expect(IbmAppconfigurationRubySdk::Logger.instance.debug).to be(true)
    end

    it "sets it to false when called with false" do
      app_config.set_debug(true)
      app_config.set_debug(false)
      expect(IbmAppconfigurationRubySdk::Logger.instance.debug).to be(false)
    end

    it "also updates the Configuration object" do
      app_config.set_debug(true)
      expect(described_class.configuration.debug).to be(true)
      app_config.set_debug(false)
    end
  end

  # ──────────────────────────────────────────────────────────
  # #use_private_endpoint
  # ──────────────────────────────────────────────────────────
  describe "#use_private_endpoint" do
    it "sets the internal flag to true" do
      app_config.use_private_endpoint(true)
      expect(app_config.instance_variable_get(:@use_private_endpoint)).to be(true)
    end

    it "sets the internal flag to false" do
      app_config.use_private_endpoint(false)
      expect(app_config.instance_variable_get(:@use_private_endpoint)).to be(false)
    end

    it "logs an error and does not change the flag for a non-boolean" do
      original = app_config.instance_variable_get(:@use_private_endpoint)
      logger = IbmAppconfigurationRubySdk::Logger.instance
      expect(logger).to receive(:error).once
      app_config.use_private_endpoint("yes")
      expect(app_config.instance_variable_get(:@use_private_endpoint)).to eq(original)
    end
  end

  # ──────────────────────────────────────────────────────────
  # #register_configuration_update_listener
  # ──────────────────────────────────────────────────────────
  describe "#register_configuration_update_listener" do
    it "logs an error when called before init" do
      logger = IbmAppconfigurationRubySdk::Logger.instance
      expect(logger).to receive(:error).once
      app_config.register_configuration_update_listener {}
    end

    it "delegates to handler when initialized" do
      app_config.init(region: "r", guid: "g", apikey: "k")
      expect(handler_double).to receive(:register_configuration_update_listener)
      app_config.register_configuration_update_listener {}
    end
  end

  # ──────────────────────────────────────────────────────────
  # #track
  # ──────────────────────────────────────────────────────────
  describe "#track" do
    it "returns nil and logs when not initialized" do
      expect(app_config.track("event", "entity")).to be_nil
    end

    it "delegates to handler when fully initialized" do
      app_config.init(region: "r", guid: "g", apikey: "k")
      app_config.instance_variable_set(:@context_initialized, true)
      expect(handler_double).to receive(:track).with("event", "entity")
      app_config.track("event", "entity")
    end
  end
end
