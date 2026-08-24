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

module IbmAppconfigurationRubySdk
  ##
  # Holds all SDK-wide options with sensible defaults.
  # Values are read from environment variables when present, falling back to the
  # constants defined here.
  #
  # @example
  #   IbmAppconfigurationRubySdk::AppConfiguration.configure do |config|
  #     config.use_private_endpoint = true
  #     config.debug = true
  #   end
  class Configuration
    ##
    # @return [Boolean] Whether the SDK connects via IBM Cloud private endpoint
    attr_accessor :use_private_endpoint

    ##
    # @return [Boolean] Whether debug-level logging is enabled
    attr_accessor :debug

    ##
    # @return [::Logger, nil] Any ::Logger-compatible object to receive SDK log output.
    #   When nil (the default) the SDK creates a plain ::Logger writing to $stdout.
    #   Set this in the configure block to route SDK messages through your own pipeline:
    #
    #   @example
    #     IbmAppconfigurationRubySdk::AppConfiguration.configure do |config|
    #       config.logger = Rails.logger
    #     end
    attr_accessor :logger

    def initialize
      @use_private_endpoint = ENV.fetch("IBM_APPCONFIGURATION_PRIVATE_ENDPOINT", false)
      @debug                = ENV.fetch("IBM_APPCONFIGURATION_DEBUG", false)
      @logger               = nil
    end
  end
end
