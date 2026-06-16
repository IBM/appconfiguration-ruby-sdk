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

# Logger class for SDK logging with color-coded output
require 'singleton'

class Logger
  include Singleton

  @debug = false

  class << self
    # Enable or disable debug logging
    # @param value [Boolean] true to enable debug logging, false to disable
    def set_debug(value = false)
      @debug = value
    end

    # Check if debug logging is enabled
    # @return [Boolean] true if debug is enabled, false otherwise
    def debug?
      @debug
    end
  end

  # Generate timestamp for log messages
  # @return [String] formatted timestamp
  def timestamp
    Time.now.strftime('%Y-%m-%d %H:%M:%S') + ' AppConfiguration'
  end

  # Log debug message (only if debug is enabled)
  # @param message [String] the message to log
  def log(message)
    return unless self.class.debug?

    puts "#{timestamp} DEBUG #{message}"
  end

  # Log error message (always shown)
  # @param message [String] the error message to log
  def error(message)
    puts "#{timestamp} ERROR #{colorize(message, :red)}"
  end

  # Log warning message (only if debug is enabled)
  # @param message [String] the warning message to log
  def warning(message)
    return unless self.class.debug?

    puts "#{timestamp} WARNING #{colorize(message, :yellow)}"
  end

  # Log success message (only if debug is enabled)
  # @param message [String] the success message to log
  def success(message)
    return unless self.class.debug?

    puts "#{timestamp} SUCCESS #{colorize(message, :green)}"
  end

  # Log info message (always shown)
  # @param message [String] the info message to log
  def info(message)
    puts "#{timestamp} INFO #{colorize(message, :blue)}"
  end

  private

  # Colorize text for terminal output
  # @param text [String] the text to colorize
  # @param color [Symbol] the color to apply (:red, :green, :yellow, :blue)
  # @return [String] colorized text
  def colorize(text, color)
    color_codes = {
      red: "\e[1;31m",
      green: "\e[1;32m",
      yellow: "\e[1;33m",
      blue: "\e[1;44m",
      reset: "\e[0m"
    }

    "#{color_codes[color]}#{text}#{color_codes[:reset]}"
  end
end
