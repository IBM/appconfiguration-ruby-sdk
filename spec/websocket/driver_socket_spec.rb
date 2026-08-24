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

RSpec.describe IbmAppconfigurationRubySdk::DriverSocket do
  let(:tcp_socket) { double("TCPSocket") }
  subject(:driver_socket) { described_class.new(tcp_socket, "wss://example.com/ws") }

  describe "#url" do
    it "returns the URL passed to the constructor" do
      expect(driver_socket.url).to eq("wss://example.com/ws")
    end
  end

  describe "#write" do
    it "delegates write to the underlying TCP socket" do
      expect(tcp_socket).to receive(:write).with("some data")
      driver_socket.write("some data")
    end

    it "passes binary data through unchanged" do
      binary = "\x00\x01\x02"
      expect(tcp_socket).to receive(:write).with(binary)
      driver_socket.write(binary)
    end
  end
end
