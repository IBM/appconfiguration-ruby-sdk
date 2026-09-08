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

# Logger class for SDK logging — delegates to stdlib ::Logger
require "logger"
require "singleton"

module IbmAppconfigurationRubySdk
  # Logger class for SDK logging — delegates to stdlib ::Logger
  class Logger
    include Singleton

    # @return [Boolean] whether debug-level logging is enabled
    attr_reader :debug

    def initialize
      @debug = false
      @log   = ::Logger.new($stdout)
      @log.progname  = "AppConfiguration"
      @log.level     = ::Logger::INFO
      @log.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.strftime("%Y-%m-%d %H:%M:%S")} #{progname} #{severity} #{msg}\n"
      end
    end

    # Backward-compatible class-level shim — delegates to the singleton instance.
    # @param value [Boolean]
    def self.set_debug(value: false)
      instance.debug = value
    end

    # Set debug mode and sync the underlying log level.
    # @param value [Boolean]
    def debug=(value)
      @debug     = value
      @log.level = value ? ::Logger::DEBUG : ::Logger::INFO
    end

    # Log a debug message (only when debug is enabled).
    # @param message [String]
    def log(message)
      return unless @debug

      @log.debug(message)
    end

    # Log an error message (always emitted).
    # @param message [String]
    def error(message)
      @log.error(message)
    end

    # Log a warning message (only when debug is enabled).
    # @param message [String]
    def warning(message)
      return unless @debug

      @log.warn(message)
    end

    # Log a success/progress message (only when debug is enabled).
    # @param message [String]
    def success(message)
      return unless @debug

      @log.info(message)
    end

    # Log an informational message (always emitted).
    # @param message [String]
    def info(message)
      @log.info(message)
    end
  end
end
