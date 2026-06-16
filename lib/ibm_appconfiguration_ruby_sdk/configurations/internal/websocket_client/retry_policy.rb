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

class RetryPolicy
  RETRY_CONFIG = {
    initial_delay: 15,
    max_delay: 3600,
    multiplier: 2,
    jitter_factor: 0.3
  }.freeze

  def self.next_delay(attempt)
    base_delay =
      RETRY_CONFIG[:initial_delay] *
      (RETRY_CONFIG[:multiplier]**attempt)

    capped_delay = [
      base_delay,
      RETRY_CONFIG[:max_delay]
    ].min

    jitter =
      capped_delay *
      RETRY_CONFIG[:jitter_factor] *
      rand

    capped_delay + jitter
  end
end
