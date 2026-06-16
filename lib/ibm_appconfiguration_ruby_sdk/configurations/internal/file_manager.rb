# Copyright 2026 IBM Corp. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# frozen_string_literal: true

require "singleton"
require_relative "logger"

# This module provides methods that perform the store and retrieve operations on the
# file based cache of the SDK.
class FileManager
  include Singleton

  def initialize
    @logger = Logger.instance
  end

  def store_files(json, file_path)
    File.write(file_path, json)
  end

  def read_persistent_cache_configurations(file_path)
    unless File.exist?(file_path)
      @logger.log("configuration file in the persistent cache doesn't exist")
      return ""
    end

    data = File.read(file_path).strip

    if data.empty?
      @logger.log("configuration file in the persistent cache is empty")
      return ""
    end

    data
  rescue StandardError
    ""
  end

  def read_bootstrap_configurations_from_file(file_path)
    raise "given bootstrap file path doesn't exist: #{file_path}" unless File.exist?(file_path)

    data = File.read(file_path).strip

    raise "given bootstrap file is empty: #{file_path}" if data.empty?

    begin
      data
    rescue StandardError => e
      raise "failed to parse the json from the given bootstrap file: #{file_path}. Error #{e}"
    end
  end

  def delete_file_data(file_path)
    return unless File.exist?(file_path)

    File.truncate(file_path, 0)
  rescue StandardError => e
    @logger.warning(e)
  end
end
