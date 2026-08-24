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

RSpec.describe IbmAppconfigurationRubySdk::RetryPolicy do
  describe "RETRY_CONFIG constants" do
    it "has initial_delay of 15 seconds" do
      expect(described_class::RETRY_CONFIG[:initial_delay]).to eq(15)
    end

    it "has max_delay of 3600 seconds (1 hour)" do
      expect(described_class::RETRY_CONFIG[:max_delay]).to eq(3600)
    end

    it "has multiplier of 2" do
      expect(described_class::RETRY_CONFIG[:multiplier]).to eq(2)
    end

    it "has jitter_factor of 0.3" do
      expect(described_class::RETRY_CONFIG[:jitter_factor]).to eq(0.3)
    end
  end

  describe ".next_delay" do
    context "with jitter seeded to 0 (deterministic lower bound)" do
      before { allow(described_class).to receive(:rand).and_return(0) }

      it "returns exactly the base delay at attempt 0 (15 * 2^0 = 15)" do
        expect(described_class.next_delay(0)).to eq(15)
      end

      it "returns exactly 30 at attempt 1 (15 * 2^1 = 30)" do
        expect(described_class.next_delay(1)).to eq(30)
      end

      it "returns exactly 60 at attempt 2 (15 * 2^2 = 60)" do
        expect(described_class.next_delay(2)).to eq(60)
      end

      it "returns exactly 3600 when the base would exceed max_delay" do
        # 15 * 2^10 = 15360, capped at 3600
        expect(described_class.next_delay(10)).to eq(3600)
      end
    end

    context "with jitter seeded to 1 (upper bound)" do
      before { allow(described_class).to receive(:rand).and_return(1) }

      it "adds 30% jitter to the capped delay at attempt 0" do
        # base = 15, jitter = 15 * 0.3 * 1 = 4.5, total = 19.5
        expect(described_class.next_delay(0)).to eq(15 + 15 * 0.3)
      end

      it "never exceeds max_delay + max_delay * jitter_factor" do
        # 3600 + 3600 * 0.3 = 4680
        expect(described_class.next_delay(20)).to be <= 4680
      end
    end

    context "with actual randomness" do
      it "delay at attempt 0 is in the range [15, 19.5]" do
        delay = described_class.next_delay(0)
        expect(delay).to be >= 15
        expect(delay).to be <= 19.5
      end

      it "delay at attempt 1 is in the range [30, 39]" do
        delay = described_class.next_delay(1)
        expect(delay).to be >= 30
        expect(delay).to be <= 39
      end

      it "is always >= initial_delay (jitter is additive only)" do
        10.times do
          expect(described_class.next_delay(0)).to be >= 15
        end
      end

      it "is always <= max_delay * (1 + jitter_factor) for large attempts" do
        expect(described_class.next_delay(50)).to be <= 3600 * 1.3
      end
    end
  end
end
