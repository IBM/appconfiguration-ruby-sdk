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

RSpec.describe IbmAppconfigurationRubySdk::Configuration do
  # Each test constructs a fresh Configuration so ENV-var stubs take effect.
  subject(:config) { described_class.new }

  describe "defaults" do
    it "sets use_private_endpoint to false when the ENV var is absent" do
      expect(config.use_private_endpoint).to eq(false)
    end

    it "sets debug to false when the ENV var is absent" do
      expect(config.debug).to eq(false)
    end
  end

  describe "ENV overrides" do
    context "when IBM_APPCONFIGURATION_PRIVATE_ENDPOINT is set" do
      around do |example|
        original = ENV["IBM_APPCONFIGURATION_PRIVATE_ENDPOINT"]
        ENV["IBM_APPCONFIGURATION_PRIVATE_ENDPOINT"] = "true"
        example.run
      ensure
        original.nil? ? ENV.delete("IBM_APPCONFIGURATION_PRIVATE_ENDPOINT") : ENV["IBM_APPCONFIGURATION_PRIVATE_ENDPOINT"] = original
      end

      it "reads the environment variable" do
        expect(described_class.new.use_private_endpoint).to eq("true")
      end
    end

    context "when IBM_APPCONFIGURATION_DEBUG is set" do
      around do |example|
        original = ENV["IBM_APPCONFIGURATION_DEBUG"]
        ENV["IBM_APPCONFIGURATION_DEBUG"] = "true"
        example.run
      ensure
        original.nil? ? ENV.delete("IBM_APPCONFIGURATION_DEBUG") : ENV["IBM_APPCONFIGURATION_DEBUG"] = original
      end

      it "reads the environment variable" do
        expect(described_class.new.debug).to eq("true")
      end
    end
  end

  describe "attr_accessor setters" do
    it "allows use_private_endpoint= to be changed" do
      config.use_private_endpoint = true
      expect(config.use_private_endpoint).to be(true)
    end

    it "allows debug= to be changed" do
      config.debug = true
      expect(config.debug).to be(true)
    end
  end
end
