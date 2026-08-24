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

require "socket"
require "openssl"
require "uri"
require "websocket/driver"
require_relative "driver_socket"
require_relative "retry_policy"
require_relative "watchdog"
require_relative "state"
require_relative "../api_manager"
require_relative "../url_builder"
require_relative "../config_fetcher"
require_relative "../background_retry_manager"
require_relative "../configuration_handler"
require_relative "../utils"
require_relative "../logger"
require_relative "../version"

module IbmAppconfigurationRubySdk
class ConnectionManager
  attr_reader :last_heartbeat_at

  def initialize(region:, guid:, apikey:, collection_id:, environment_id:, start_background_retry: false)
    @region = region
    @guid = guid
    @apikey = apikey
    @collection_id = collection_id
    @environment_id = environment_id
    @start_background_retry = start_background_retry

    @state = IbmAppconfigurationRubySdk::State::DISCONNECTED

    @state_mutex = Mutex.new

    @reconnect_attempts = 0

    @should_reconnect = true

    @socket = nil
    @driver = nil

    @reader_thread = nil
    @watchdog_thread = nil

    @last_heartbeat_at = Time.now

    # Initialize ConfigFetcher and BackgroundRetryManager
    @config_fetcher = nil
    @background_retry_manager = nil

    @logger = IbmAppconfigurationRubySdk::Logger.instance

    # Setup SDK components
    setup_sdk
  end

  def connect
    @shutting_down = false

    transition_state(State::CONNECTING)

    # Get authentication token
    begin
      @logger.log(Constants::WEBSOCKET_INITIATING_CONNECTION)
      bearer_token = ApiManager.token

      if bearer_token.nil? || bearer_token.empty?
        @logger.error(Constants::WEBSOCKET_AUTH_TOKEN_FAILED)
        transition_state(State::RECONNECTING)
        schedule_reconnect
        return
      end

      @logger.log(Constants::WEBSOCKET_AUTH_TOKEN_SUCCESS)
    rescue StandardError => e
      @logger.error("Exception getting authentication token: #{e.class.name} - #{e.message}")
      transition_state(State::RECONNECTING)
      schedule_reconnect
      return
    end

    # Get WebSocket URL
    url = @url_builder.websocket_url

    if url.nil? || url.empty?
      @logger.error(Constants::WEBSOCKET_URL_FAILED)
      transition_state(State::RECONNECTING)
      schedule_reconnect
      return
    end

    uri = URI.parse(url)

    host = uri.host
    port = uri.port || (uri.scheme == "wss" ? 443 : 80)

    # Create TCP socket
    tcp_socket = TCPSocket.new(host, port)

    # Wrap with SSL only for wss://, use plain TCP for ws://
    if uri.scheme == "wss"
      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)

      raw_socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, ssl_context)
      raw_socket.sync_close = true
      raw_socket.hostname = host # Set SNI hostname for SSL handshake
      raw_socket.connect
    else
      raw_socket = tcp_socket
    end

    # Create driver socket with full URL
    socket = IbmAppconfigurationRubySdk::DriverSocket.new(raw_socket, url)

    @socket = raw_socket

    @driver = WebSocket::Driver.client(socket)

    # Set authentication headers
    @driver.set_header("Authorization", bearer_token)
    @driver.set_header("User-Agent", "appconfiguration-ruby-sdk/#{IbmAppconfigurationRubySdk::VERSION}")
    register_callbacks

    @driver.start

    @logger.log(Constants::WEBSOCKET_REQUEST_SENT)

    start_reader_thread

    # Start background retry if flag is set (fallback configurations were loaded)
    if @start_background_retry
      @background_retry_manager.start(
        reason: "Initial config API fetch failed - using fallback configuration"
      )
    end
    @start_background_retry = true
  rescue StandardError => e
    @logger.error("Websocket Connection failed: #{e.class.name} - #{e.message}")

    transition_state(
      IbmAppconfigurationRubySdk::State::RECONNECTING
    )

    schedule_reconnect
  end

  def disconnect
    @should_reconnect = false

    transition_state(IbmAppconfigurationRubySdk::State::CLOSING)

    cleanup_connection

    transition_state(IbmAppconfigurationRubySdk::State::CLOSED)
  end

  def connected?
    @state == IbmAppconfigurationRubySdk::State::CONNECTED
  end

  # --------------------------------------------------
  # INTERNAL CALLBACKS
  # --------------------------------------------------

  def register_callbacks
    @driver.on(:open) do |event|
      @logger.info(Constants::WEBSOCKET_CONNECTED)

      # Check for HTTP status code during WebSocket handshake
      # The event object may contain status_code for HTTP errors
      if event.respond_to?(:status_code) && event.status_code
        status_code = event.status_code

        # Check for client-side errors (4xx except 429 Too Many Requests)
        if status_code >= 400 && status_code < 500 && status_code != 429
          @logger.error("WebSocket handshake failed with client error: #{status_code} - will not retry")
          @should_reconnect = false
          cleanup_connection
          transition_state(IbmAppconfigurationRubySdk::State::CLOSED)
          return
        end
      end

      @logger.log(Constants::WEBSOCKET_CONNECTION_RESET_WATCHDOG)

      transition_state(IbmAppconfigurationRubySdk::State::CONNECTED)

      @logger.info(Constants::WEBSOCKET_ESTABLISHED)

      @reconnect_attempts = 0

      @last_heartbeat_at = Time.now

      start_watchdog_thread

      # Incase of websocket retry we need to call /config again
      @start_background_retry = true
    end

    @driver.on(:message) do |event|
      @logger.log("Received: #{event.data}")

      if event.data == "test message"
        # Heartbeat message
        @last_heartbeat_at = Time.now
        @logger.log(Constants::WEBSOCKET_HEARTBEAT_UPDATED)
      else
        # Configuration update message
        @logger.info(Constants::WEBSOCKET_CONFIG_UPDATE_RECEIVED)

        # Stop any active background retry and restart from t=0
        if @background_retry_manager.active?
          @logger.log(Constants::WEBSOCKET_STOP_ACTIVE_BACKGROUND_RETRY)
          @background_retry_manager.stop
        end

        # Start background retry manager which will fetch immediately at t=0
        @background_retry_manager.start(
          reason: "Configuration update notification received"
        )
        @logger.log(Constants::WEBSOCKET_BACKGROUND_RETRY_STARTED)
      end
    end

    @driver.on(:close) do |event|
      @logger.log(Constants::WEBSOCKET_ON_CLOSE)

      if event.code == IbmAppconfigurationRubySdk::Constants::CUSTOM_SOCKET_CLOSE_REASON_CODE
        @logger.log("Websocket connection closed by the client. Reason: #{event.code} #{event.reason}")
      end

      @logger.info("Websocket Connection closed (code: #{event.code}, reason: #{event.reason})")

      # Check for WebSocket close codes that map to HTTP 4xx client errors
      # Close codes 4000-4499 (except 4429) indicate client-side errors
      if event.code && event.code >= 4000 && event.code < 4500 && event.code != 4429
        @logger.error("WebSocket closed with client error code: #{event.code} - will not retry")
        @should_reconnect = false
        cleanup_connection
        transition_state(IbmAppconfigurationRubySdk::State::CLOSED)
        return
      end

      @should_reconnect = true
      handle_disconnect("WebSocket close")
    end

    @driver.on(:error) do |event|
      @logger.log(Constants::WEBSOCKET_ON_ERROR)
      @logger.error("WebSocket error: #{event}")

      # Check if error contains a status code indicating client-side error
      if event.respond_to?(:status_code) && event.status_code
        status_code = event.status_code

        # Check for client-side errors (4xx except 429 Too Many Requests)
        if status_code >= 400 && status_code < 500 && status_code != 429
          @logger.error("WebSocket error with client error status: #{status_code} - will not retry")
          @should_reconnect = false
          cleanup_connection
          transition_state(IbmAppconfigurationRubySdk::State::CLOSED)
          return
        end
      end

      @should_reconnect = true

      handle_disconnect("WebSocket error")
    end
  end

  def start_reader_thread
    @reader_thread =
      Thread.new do
        loop do
          break if @socket.nil?

          data = @socket.readpartial(1024)
          @driver.parse(data)
        end
      rescue EOFError
        unless @shutting_down

          @logger.warning(Constants::WEBSOCKET_SERVER_DISCONNECTED)

          handle_disconnect("EOF")

        end
      rescue IOError => e
        if e.message.include?("stream closed")

          @logger.log(Constants::WEBSOCKET_READER_THREAD_STOPPED)

        else

          @logger.error("Reader IO error: #{e.message}")

          handle_disconnect(
            "Reader IO failure"
          )

        end
      rescue StandardError => e
        unless @shutting_down

          @logger.error("Reader error: #{e.class.name} - #{e.message}")

          handle_disconnect(
            "Reader failure"
          )

        end
      end
  end

  # --------------------------------------------------
  # WATCHDOG
  # --------------------------------------------------

  def start_watchdog_thread
    watchdog = IbmAppconfigurationRubySdk::Watchdog.new(self)

    @watchdog_thread = watchdog.start
  end

  def handle_disconnect(reason)
    should_schedule = false

    @logger.error("#{Constants::WEBSOCKET_CONNECTION_LOST} (#{reason})")

    @state_mutex.synchronize do
      return if [
        IbmAppconfigurationRubySdk::State::RECONNECTING,
        IbmAppconfigurationRubySdk::State::CLOSING,
        IbmAppconfigurationRubySdk::State::CLOSED
      ].include?(@state)

      @logger.info("Handling websocket disconnect: #{reason}")

      transition_state(
        IbmAppconfigurationRubySdk::State::RECONNECTING
      )

      should_schedule =
        @should_reconnect
    end

    # Schedule reconnect FIRST
    schedule_reconnect if should_schedule

    # Then cleanup old connection
    cleanup_connection
  end

  # --------------------------------------------------
  # CLEANUP
  # --------------------------------------------------

  def cleanup_connection
    @logger.log(Constants::WEBSOCKET_CLOSING_EXISTING) if @driver

    begin
      @driver&.close
    rescue StandardError => e
      @logger.log("cleanup driver: #{e.message}")
    end

    begin
      @socket&.close
    rescue StandardError => e
      @logger.log("cleanup socket: #{e.message}")
    end

    @reader_thread.kill if @reader_thread && @reader_thread != Thread.current

    begin
      @watchdog_thread&.kill
    rescue StandardError => e
      @logger.log("cleanup watchdog: #{e.message}")
    end

    @driver = nil
    @socket = nil

    @reader_thread = nil
    @watchdog_thread = nil
  end

  # --------------------------------------------------
  # RECONNECT
  # --------------------------------------------------

  def schedule_reconnect
    delay =
      IbmAppconfigurationRubySdk::RetryPolicy.next_delay(
        @reconnect_attempts
      )

    @logger.info("Websocket reconnect in #{delay.round(2)} sec")

    @reconnect_attempts += 1

    Thread.new do
      sleep(delay)

      connect if @should_reconnect
    end
  end

  # --------------------------------------------------
  # STATE
  # --------------------------------------------------

  def transition_state(new_state)
    @logger.log("#{@state} -> #{new_state}")

    @state = new_state
  end

  # --------------------------------------------------
  # SETUP
  # --------------------------------------------------

  private

  def setup_sdk
    # Configure UrlBuilder
    @url_builder = IbmAppconfigurationRubySdk::UrlBuilder.instance
    @url_builder.region = @region
    @url_builder.guid = @guid
    @url_builder.apikey = @apikey
    @url_builder.set_websocket_url(@collection_id, @environment_id)

    # Configure ApiManager
    IbmAppconfigurationRubySdk::ApiManager.set_authenticator

    # Initialize ConfigFetcher
    @config_fetcher = IbmAppconfigurationRubySdk::ConfigFetcher.new(
      collection_id: @collection_id,
      environment_id: @environment_id,
      handler: IbmAppconfigurationRubySdk::ConfigurationHandler.instance
    )

    # Initialize BackgroundRetryManager
    @background_retry_manager = IbmAppconfigurationRubySdk::BackgroundRetryManager.new(
      collection_id: @collection_id,
      environment_id: @environment_id,
      handler: IbmAppconfigurationRubySdk::ConfigurationHandler.instance
    )
  end
end
end
