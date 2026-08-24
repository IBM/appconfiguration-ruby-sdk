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

RSpec.describe IbmAppconfigurationRubySdk::FileManager do
  subject(:file_manager) { described_class.instance }

  describe "#store_files" do
    it "calls File.write with the given path and content" do
      expect(File).to receive(:write).with("/tmp/cache.json", '{"key":"val"}')
      file_manager.store_files('{"key":"val"}', "/tmp/cache.json")
    end
  end

  describe "#read_persistent_cache_configurations" do
    context "when the file does not exist" do
      before { allow(File).to receive(:exist?).and_return(false) }

      it "returns an empty string" do
        expect(file_manager.read_persistent_cache_configurations("/tmp/missing.json")).to eq("")
      end
    end

    context "when the file exists and has content" do
      before do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return('{"features":[]}')
      end

      it "returns the file content" do
        expect(file_manager.read_persistent_cache_configurations("/tmp/cache.json"))
          .to eq('{"features":[]}')
      end
    end

    context "when the file exists but is empty" do
      before do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return("   ")
      end

      it "returns an empty string" do
        expect(file_manager.read_persistent_cache_configurations("/tmp/empty.json")).to eq("")
      end
    end

    context "when reading raises a StandardError" do
      before do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_raise(StandardError, "permission denied")
      end

      it "silently returns an empty string" do
        expect(file_manager.read_persistent_cache_configurations("/tmp/broken.json")).to eq("")
      end
    end
  end

  describe "#read_bootstrap_configurations_from_file" do
    context "when the file does not exist" do
      before { allow(File).to receive(:exist?).and_return(false) }

      it "raises a RuntimeError" do
        expect { file_manager.read_bootstrap_configurations_from_file("/tmp/nope.json") }
          .to raise_error(RuntimeError, /doesn't exist/)
      end
    end

    context "when the file exists but is empty" do
      before do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return("  ")
      end

      it "raises a RuntimeError" do
        expect { file_manager.read_bootstrap_configurations_from_file("/tmp/empty.json") }
          .to raise_error(RuntimeError, /is empty/)
      end
    end

    context "when the file exists and has content" do
      before do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return('{"features":[]}')
      end

      it "returns the content" do
        expect(file_manager.read_bootstrap_configurations_from_file("/tmp/boot.json"))
          .to eq('{"features":[]}')
      end
    end
  end

  describe "#delete_file_data" do
    context "when the file does not exist" do
      before { allow(File).to receive(:exist?).and_return(false) }

      it "does not call File.truncate" do
        expect(File).not_to receive(:truncate)
        file_manager.delete_file_data("/tmp/nope.json")
      end
    end

    context "when the file exists" do
      before { allow(File).to receive(:exist?).and_return(true) }

      it "truncates the file to 0 bytes" do
        expect(File).to receive(:truncate).with("/tmp/cache.json", 0)
        file_manager.delete_file_data("/tmp/cache.json")
      end

      it "silently rescues a StandardError from File.truncate" do
        allow(File).to receive(:truncate).and_raise(StandardError, "read-only filesystem")
        expect { file_manager.delete_file_data("/tmp/cache.json") }.not_to raise_error
      end
    end
  end
end
