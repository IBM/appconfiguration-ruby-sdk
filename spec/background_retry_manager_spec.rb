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

RSpec.describe IbmAppconfigurationRubySdk::BackgroundRetryManager do
  let(:handler_double)  { instance_double(IbmAppconfigurationRubySdk::ConfigurationHandler) }
  let(:logger_double)   { instance_double(IbmAppconfigurationRubySdk::Logger, log: nil, info: nil, warning: nil, error: nil) }
  let(:fetcher_double)  { instance_double(IbmAppconfigurationRubySdk::ConfigFetcher) }

  subject(:manager) do
    allow(IbmAppconfigurationRubySdk::ConfigFetcher).to receive(:new).and_return(fetcher_double)
    described_class.new(
      collection_id: "col",
      environment_id: "dev",
      handler: handler_double,
      logger: logger_double
    )
  end

  # ──────────────────────────────────────────────────────────
  # Initial state
  # ──────────────────────────────────────────────────────────
  describe "initial state" do
    it "is not active" do
      expect(manager.active?).to be(false)
    end

    it "has current_attempt of 0" do
      expect(manager.current_attempt).to eq(0)
    end
  end

  # ──────────────────────────────────────────────────────────
  # #start
  # ──────────────────────────────────────────────────────────
  describe "#start" do
    before do
      # Make the fetcher block indefinitely so threads don't run during the test.
      allow(fetcher_double).to receive(:fetch) { sleep(9999) }
      # stub Thread.new to prevent real background threads
      allow(Thread).to receive(:new).and_return(double("Thread", alive?: false))
    end

    it "returns true when not yet active" do
      expect(manager.start(reason: "test")).to be(true)
    end

    it "sets active? to true" do
      manager.start(reason: "test")
      expect(manager.active?).to be(true)
    end

    it "returns false when already active (idempotent)" do
      manager.start(reason: "first")
      expect(manager.start(reason: "second")).to be(false)
    end
  end

  # ──────────────────────────────────────────────────────────
  # #stop
  # ──────────────────────────────────────────────────────────
  describe "#stop" do
    before do
      allow(Thread).to receive(:new).and_return(double("Thread", alive?: false))
      manager.start(reason: "test")
    end

    it "sets active? to false" do
      manager.stop
      expect(manager.active?).to be(false)
    end

    it "resets current_attempt to 0" do
      manager.stop
      expect(manager.current_attempt).to eq(0)
    end

    it "is idempotent — calling stop twice does not raise" do
      manager.stop
      expect { manager.stop }.not_to raise_error
    end
  end

  # ──────────────────────────────────────────────────────────
  # Delay math (private methods via send)
  # ──────────────────────────────────────────────────────────
  describe "delay math" do
    describe "#compute_base_delay_ms" do
      it "returns a value in the 2–2.9 minute range (120_000 to 174_000 ms)" do
        10.times do
          val = manager.send(:compute_base_delay_ms)
          expect(val).to be >= 120_000
          expect(val).to be < 174_001
        end
      end
    end

    describe "#compute_cap_delay_ms" do
      it "returns a value in the 60–60:59 minute range" do
        10.times do
          val = manager.send(:compute_cap_delay_ms)
          expect(val).to be >= 3_600_000
          expect(val).to be <= 3_659_000
        end
      end
    end

    describe "#compute_next_delay_ms" do
      it "returns the base delay at attempt 1" do
        cap_ms = manager.send(:compute_cap_delay_ms)
        result = manager.send(:compute_next_delay_ms, 1, cap_ms)
        # At attempt 1: base * 2^(1-1) = base * 1 = base (120_000 ms minimum) capped at cap.
        # Use the fixed lower bound 120_000 to avoid comparing two independent
        # jitter-bearing calls to compute_base_delay_ms.
        expect(result).to be <= cap_ms
        expect(result).to be >= 120_000
      end

      it "caps the delay at the provided cap" do
        cap_ms = 100
        result = manager.send(:compute_next_delay_ms, 50, cap_ms)
        expect(result).to eq(cap_ms)
      end
    end
  end

  # ──────────────────────────────────────────────────────────
  # Success path — stops after successful fetch
  # ──────────────────────────────────────────────────────────
  describe "success path" do
    it "calls process_and_load_configurations and then stops when fetch succeeds" do
      data = { features: [] }
      allow(fetcher_double).to receive(:fetch).and_return({ ok: true, retryable: false, status: 200, data: data })
      allow(fetcher_double).to receive(:process_and_load_configurations).and_return(true)
      # Stub rand so jitter is 0 — prevents the thread from sleeping up to 5s.
      allow(manager).to receive(:rand).and_return(0)

      manager.start(reason: "test")
      # Give the background thread a moment to complete.
      sleep(0.1)

      expect(fetcher_double).to have_received(:process_and_load_configurations).with(data)
      expect(manager.active?).to be(false)
    end
  end
end
