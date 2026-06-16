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

class Watchdog
  WATCHDOG_CONFIG = {
    check_interval: 60,
    heartbeat_timeout: 120
  }.freeze

  def initialize(client)
    @client = client
  end

  def start
    Thread.new do
      loop do
        sleep WATCHDOG_CONFIG[:check_interval]

        break unless @client.connected?

        heartbeat_age =
          Time.now - @client.last_heartbeat_at

        next unless heartbeat_age >
                    WATCHDOG_CONFIG[:heartbeat_timeout]

        puts "Heartbeat timeout detected"

        @client.handle_disconnect(
          "Heartbeat timeout"
        )

        break
      end
    end
  end
end
