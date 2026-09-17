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

RSpec.describe IbmAppconfigurationRubySdk do
  describe "Error" do
    it "is a subclass of StandardError" do
      expect(described_module::Error.ancestors).to include(StandardError)
    end
  end

  describe "ConfigurationError" do
    it "is a subclass of Error" do
      expect(described_module::ConfigurationError.ancestors).to include(described_module::Error)
    end

    it "can be raised with a message" do
      expect { raise described_module::ConfigurationError.new("bad config") }
        .to raise_error(described_module::ConfigurationError, "bad config")
    end
  end

  describe IbmAppconfigurationRubySdk::APIError do
    it "stores http_status and http_body" do
      err = described_class.new("oops", http_status: 404, http_body: '{"error":"not found"}')
      expect(err.http_status).to eq(404)
      expect(err.http_body).to eq('{"error":"not found"}')
      expect(err.message).to eq("oops")
    end

    it "defaults http_status and http_body to nil" do
      err = described_class.new("oops")
      expect(err.http_status).to be_nil
      expect(err.http_body).to be_nil
    end

    describe ".from_status" do
      it "returns AuthenticationError for 401" do
        err = described_class.from_status(401)
        expect(err).to be_a(IbmAppconfigurationRubySdk::AuthenticationError)
        expect(err.http_status).to eq(401)
      end

      it "returns RateLimitError for 429" do
        err = described_class.from_status(429)
        expect(err).to be_a(IbmAppconfigurationRubySdk::RateLimitError)
        expect(err.http_status).to eq(429)
      end

      it "returns InvalidRequestError for 400" do
        err = described_class.from_status(400)
        expect(err).to be_a(IbmAppconfigurationRubySdk::InvalidRequestError)
        expect(err.http_status).to eq(400)
      end

      it "returns InvalidRequestError for 422" do
        err = described_class.from_status(422)
        expect(err).to be_a(IbmAppconfigurationRubySdk::InvalidRequestError)
        expect(err.http_status).to eq(422)
      end

      it "returns ServerError for 500" do
        err = described_class.from_status(500)
        expect(err).to be_a(IbmAppconfigurationRubySdk::ServerError)
        expect(err.http_status).to eq(500)
      end

      it "returns ServerError for 503" do
        err = described_class.from_status(503)
        expect(err).to be_a(IbmAppconfigurationRubySdk::ServerError)
      end

      it "returns plain APIError for 404" do
        err = described_class.from_status(404)
        expect(err.class).to eq(described_class)
        expect(err.http_status).to eq(404)
      end

      it "returns plain APIError for 302" do
        err = described_class.from_status(302)
        expect(err.class).to eq(described_class)
      end

      it "uses the default message 'HTTP <status>' when no message is given" do
        err = described_class.from_status(404)
        expect(err.message).to eq("HTTP 404")
      end

      it "uses the given message when provided" do
        err = described_class.from_status(401, message: "token expired")
        expect(err.message).to eq("token expired")
      end

      it "stores the body" do
        err = described_class.from_status(500, body: "Internal Server Error")
        expect(err.http_body).to eq("Internal Server Error")
      end
    end
  end

  describe IbmAppconfigurationRubySdk::AuthenticationError do
    it "is a subclass of APIError" do
      expect(described_class.ancestors).to include(IbmAppconfigurationRubySdk::APIError)
    end
  end

  describe IbmAppconfigurationRubySdk::RateLimitError do
    it "is a subclass of APIError" do
      expect(described_class.ancestors).to include(IbmAppconfigurationRubySdk::APIError)
    end
  end

  describe IbmAppconfigurationRubySdk::InvalidRequestError do
    it "is a subclass of APIError" do
      expect(described_class.ancestors).to include(IbmAppconfigurationRubySdk::APIError)
    end
  end

  describe IbmAppconfigurationRubySdk::ServerError do
    it "is a subclass of APIError" do
      expect(described_class.ancestors).to include(IbmAppconfigurationRubySdk::APIError)
    end
  end

  def described_module
    IbmAppconfigurationRubySdk
  end
end
