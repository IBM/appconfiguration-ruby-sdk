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

RSpec.describe IbmAppconfigurationRubySdk::SecretProperty do
  subject(:secret_property) { described_class.new("my-secret-prop") }

  it "exposes property_id" do
    expect(secret_property.property_id).to eq("my-secret-prop")
  end

  describe "#get_current_value" do
    it "returns nil when entity_id is nil" do
      expect(secret_property.get_current_value(nil)).to be_nil
    end

    it "returns nil when entity_id is blank" do
      expect(secret_property.get_current_value("   ")).to be_nil
      expect(secret_property.get_current_value("")).to be_nil
    end

    context "with a valid entity_id" do
      let(:handler_double) { instance_double(IbmAppconfigurationRubySdk::ConfigurationHandler) }

      before do
        allow(IbmAppconfigurationRubySdk::ConfigurationHandler)
          .to receive(:instance).and_return(handler_double)
      end

      it "returns nil when the property is not found in the handler" do
        allow(handler_double).to receive(:get_property).with("my-secret-prop").and_return(nil)
        expect(secret_property.get_current_value("user-1")).to be_nil
      end

      context "when the property exists" do
        let(:property_double) do
          instance_double(IbmAppconfigurationRubySdk::Property, name: "My Secret", property_id: "my-secret-prop")
        end
        let(:eval_result_with_id) do
          IbmAppconfigurationRubySdk::EvaluationResult.new(
            value: { id: "secret-123" },
            enabled: nil,
            details: IbmAppconfigurationRubySdk::EvaluationDetails.new(value_type: "DEFAULT_VALUE")
          )
        end

        before do
          allow(handler_double).to receive(:get_property).with("my-secret-prop").and_return(property_double)
          allow(property_double).to receive(:get_current_value).and_return(eval_result_with_id)
        end

        it "returns nil when get_current_value on the property returns nil" do
          allow(property_double).to receive(:get_current_value).and_return(nil)
          expect(secret_property.get_current_value("user-1")).to be_nil
        end

        it "returns nil when the value has no :id key" do
          result_no_id = IbmAppconfigurationRubySdk::EvaluationResult.new(
            value: { not_id: "foo" },
            enabled: nil,
            details: IbmAppconfigurationRubySdk::EvaluationDetails.new(value_type: "DEFAULT_VALUE")
          )
          allow(property_double).to receive(:get_current_value).and_return(result_no_id)
          expect(secret_property.get_current_value("user-1")).to be_nil
        end

        it "returns nil when the value is not a Hash" do
          result_not_hash = IbmAppconfigurationRubySdk::EvaluationResult.new(
            value: "plain-string",
            enabled: nil,
            details: IbmAppconfigurationRubySdk::EvaluationDetails.new(value_type: "DEFAULT_VALUE")
          )
          allow(property_double).to receive(:get_current_value).and_return(result_not_hash)
          expect(secret_property.get_current_value("user-1")).to be_nil
        end

        context "when a secret manager is configured" do
          let(:secrets_manager_double) { double("SecretsManager") }
          let(:secret_response) { { value: "s3cr3t!" } }

          before do
            allow(handler_double).to receive(:get_secrets_map)
              .and_return({ "my-secret-prop" => secrets_manager_double })
            allow(secrets_manager_double).to receive(:get_secret).with(id: "secret-123")
              .and_return(secret_response)
          end

          it "calls the secrets manager with the secret ID and returns the response" do
            expect(secret_property.get_current_value("user-1")).to eq(secret_response)
          end
        end

        context "when no secret manager is configured for this property" do
          before do
            allow(handler_double).to receive(:get_secrets_map).and_return({})
          end

          it "returns nil" do
            expect(secret_property.get_current_value("user-1")).to be_nil
          end
        end
      end
    end
  end
end
