# frozen_string_literal: true

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

require_relative "../logger"

module IbmAppconfigurationRubySdk
  # Watchdog that monitors WebSocket connection health
  class Watchdog
    WATCHDOG_CONFIG = {
      check_interval: 60,
      heartbeat_timeout: 120
    }.freeze

    def initialize(client)
      @client = client
      @logger = IbmAppconfigurationRubySdk::Logger.instance
    end

    def start
      if @client.connected?
        @logger.log("Watchdog timer started - monitoring heartbeat every #{WATCHDOG_CONFIG[:check_interval]}s")
      else
        @logger.log(Constants::WATCHDOG_NOT_RUNNING)
        return Thread.new {} # no-op thread
      end

      Thread.new do
        loop do
          sleep WATCHDOG_CONFIG[:check_interval]

          break unless @client.connected?

          heartbeat_age =
            Time.now - @client.last_heartbeat_at

          next unless heartbeat_age >
                      WATCHDOG_CONFIG[:heartbeat_timeout]

          @logger.log(Constants::WATCHDOG_STOPPING)
          @logger.warning(
            "Watchdog detected stale connection - no heartbeat received for " \
            "#{heartbeat_age.round(1)}s (threshold: #{WATCHDOG_CONFIG[:heartbeat_timeout]}s)"
          )

          @client.handle_disconnect("Heartbeat timeout")

          break
        end
      end
    end
  end
end
