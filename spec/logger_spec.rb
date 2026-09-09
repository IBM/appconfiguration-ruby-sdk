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

RSpec.describe IbmAppconfigurationRubySdk::Logger do
  subject(:logger) { described_class.instance }

  let(:log_double) do
    instance_double(::Logger, debug: nil, info: nil, warn: nil, error: nil).tap do |d|
      allow(d).to receive(:level=)
    end
  end

  # Swap @log for a fresh double before each example and restore the real
  # ::Logger after, so the singleton does not carry an expired double into
  # other specs.
  let!(:real_log) { logger.instance_variable_get(:@log) }

  before do
    logger.instance_variable_set(:@log, log_double)
    logger.instance_variable_set(:@debug, false)
  end

  after do
    logger.instance_variable_set(:@log, real_log)
    logger.instance_variable_set(:@debug, false)
  end

  describe "#log (debug-gated)" do
    it "does NOT call debug when debug is false" do
      expect(log_double).not_to receive(:debug)
      logger.log("a debug message")
    end

    it "DOES call debug when debug is true" do
      logger.debug = true
      expect(log_double).to receive(:debug).with("a debug message")
      logger.log("a debug message")
    end
  end

  describe "#warning (debug-gated)" do
    it "does NOT call warn when debug is false" do
      expect(log_double).not_to receive(:warn)
      logger.warning("a warning")
    end

    it "DOES call warn when debug is true" do
      logger.debug = true
      expect(log_double).to receive(:warn).with("a warning")
      logger.warning("a warning")
    end
  end

  describe "#success (debug-gated)" do
    it "does NOT call info when debug is false" do
      expect(log_double).not_to receive(:info)
      logger.success("success!")
    end

    it "DOES call info when debug is true" do
      logger.debug = true
      expect(log_double).to receive(:info).with("success!")
      logger.success("success!")
    end
  end

  describe "#error (always-on)" do
    it "calls error even when debug is false" do
      expect(log_double).to receive(:error).with("something went wrong")
      logger.error("something went wrong")
    end
  end

  describe "#info (always-on)" do
    it "calls info even when debug is false" do
      expect(log_double).to receive(:info).with("informational message")
      logger.info("informational message")
    end
  end

  describe "#debug=" do
    it "sets @log.level to DEBUG when true" do
      expect(log_double).to receive(:level=).with(::Logger::DEBUG)
      logger.debug = true
    end

    it "sets @log.level to INFO when false" do
      expect(log_double).to receive(:level=).with(::Logger::INFO)
      logger.debug = false
    end
  end

  describe ".set_debug" do
    it "sets debug on the singleton instance" do
      described_class.set_debug(value: true)
      expect(logger.debug).to be(true)
      described_class.set_debug(value: false)
    end

    it "defaults to false when called with no argument" do
      logger.debug = true
      described_class.set_debug
      expect(logger.debug).to be(false)
    end
  end
end
