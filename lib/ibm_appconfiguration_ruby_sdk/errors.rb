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
  # Base error for all SDK errors. Rescue this to catch any SDK-raised exception.
  class Error < StandardError; end

  ##
  # Raised when the SDK is used incorrectly — e.g. calling init() with missing
  # parameters or calling set_context() before init().
  class ConfigurationError < Error; end

  ##
  # Raised for HTTP-level errors returned by the App Configuration service.
  # Carries the HTTP status code and raw response body so callers can inspect
  # the failure detail without parsing the exception message.
  class APIError < Error
    attr_reader :http_status, :http_body

    # @param msg [String] Human-readable error message
    # @param http_status [Integer, nil] HTTP status code
    # @param http_body [String, nil] Raw response body
    def initialize(msg = nil, http_status: nil, http_body: nil)
      super(msg)
      @http_status = http_status
      @http_body   = http_body
    end

    ##
    # Factory — returns the most specific APIError subclass for the given status.
    #
    # @param status [Integer] HTTP status code
    # @param body [String, nil] Raw response body
    # @param message [String, nil] Override message (defaults to "HTTP <status>")
    # @return [APIError] An instance of the appropriate subclass
    def self.from_status(status, body: nil, message: nil)
      klass = case status
              when 401        then AuthenticationError
              when 429        then RateLimitError
              when 400, 422   then InvalidRequestError
              when 500..599   then ServerError
              else                 APIError
              end
      klass.new(message || "HTTP #{status}", http_status: status, http_body: body)
    end
  end

  ## Raised when the service returns HTTP 401.
  class AuthenticationError   < APIError; end

  ## Raised when the service returns HTTP 429.
  class RateLimitError        < APIError; end

  ## Raised when the service returns HTTP 400 or 422.
  class InvalidRequestError   < APIError; end

  ## Raised when the service returns a 5xx status.
  class ServerError           < APIError; end
end
