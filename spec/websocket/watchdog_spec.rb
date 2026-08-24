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

RSpec.describe IbmAppconfigurationRubySdk::Watchdog do
  describe "WATCHDOG_CONFIG" do
    it "has a check_interval of 60 seconds" do
      expect(described_class::WATCHDOG_CONFIG[:check_interval]).to eq(60)
    end

    it "has a heartbeat_timeout of 120 seconds" do
      expect(described_class::WATCHDOG_CONFIG[:heartbeat_timeout]).to eq(120)
    end
  end

  describe "#start" do
    let(:client) { double("ConnectionManager") }
    subject(:watchdog) { described_class.new(client) }

    it "returns a Thread" do
      allow(client).to receive(:connected?).and_return(false)
      thread = watchdog.start
      thread.join(1)
      expect(thread).to be_a(Thread)
    end

    context "when the heartbeat is fresh (< 120s ago)" do
      before do
        allow(client).to receive(:connected?).and_return(true, false) # run once then exit loop
        allow(client).to receive(:last_heartbeat_at).and_return(Time.now - 10)
      end

      it "does NOT call handle_disconnect" do
        expect(client).not_to receive(:handle_disconnect)

        # Patch sleep to be instant so the thread runs without waiting 60s.
        allow_any_instance_of(described_class).to receive(:sleep)
        thread = watchdog.start
        thread.join(1)
      end
    end

    context "when the heartbeat is stale (> 120s ago)" do
      before do
        allow(client).to receive(:connected?).and_return(true)
        allow(client).to receive(:last_heartbeat_at).and_return(Time.now - 200)
      end

      it "calls handle_disconnect with a timeout reason" do
        expect(client).to receive(:handle_disconnect).with("Heartbeat timeout")

        allow_any_instance_of(described_class).to receive(:sleep)
        thread = watchdog.start
        thread.join(1)
      end
    end
  end
end
