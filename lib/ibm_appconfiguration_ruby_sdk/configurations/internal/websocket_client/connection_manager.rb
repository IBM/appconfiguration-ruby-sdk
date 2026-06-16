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
require_relative "connectivity"
require_relative "../../../core/api_manager"
require_relative "../../../core/url_builder"
require_relative "../retry_manager/config_fetcher"
require_relative "../retry_manager/background_retry_manager"
require_relative "../../configuration_handler"
require_relative "../utils"
require_relative "../../../version"

class ConnectionManager
  attr_reader :last_heartbeat_at

  def initialize(region:, guid:, apikey:, collection_id:, environment_id:, start_background_retry: false)
    @region = region
    @guid = guid
    @apikey = apikey
    @collection_id = collection_id
    @environment_id = environment_id
    @start_background_retry = start_background_retry

    @state = State::DISCONNECTED

    @state_mutex = Mutex.new

    @reconnect_attempts = 0

    @should_reconnect = true

    @socket = nil
    @driver = nil

    @reader_thread = nil
    @watchdog_thread = nil
    @connectivity_thread = nil

    @last_heartbeat_at = Time.now

    # Initialize ConfigFetcher and BackgroundRetryManager
    @config_fetcher = nil
    @background_retry_manager = nil

    # Setup SDK components
    setup_sdk
  end

  def connect
    @shutting_down = false

    transition_state(State::CONNECTING)

    # Get authentication token
    begin
      puts "⏳ Requesting IAM token..."
      bearer_token = ApiManager.token

      if bearer_token.nil? || bearer_token.empty?
        puts "❌ Failed to get authentication token"
        transition_state(State::RECONNECTING)
        schedule_reconnect
        return
      end

      puts "✓ Got authentication token"
    rescue StandardError => e
      puts "❌ Exception getting authentication token: #{e.message}"
      puts "   Error details: #{e.class.name}"
      transition_state(State::RECONNECTING)
      schedule_reconnect
      return
    end

    # Get WebSocket URL
    url = @url_builder.websocket_url

    if url.nil? || url.empty?
      puts "❌ Failed to get WebSocket URL"
      transition_state(State::RECONNECTING)
      schedule_reconnect
      return
    end

    uri = URI.parse(url)

    host = uri.host
    port = uri.port || 443 # Default to 443 for wss://

    puts "Connecting to #{host}:#{port}"

    # Create TCP socket
    tcp_socket = TCPSocket.new(host, port)

    # Wrap with SSL for wss://
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)

    ssl_socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, ssl_context)
    ssl_socket.sync_close = true
    ssl_socket.hostname = host # Set SNI hostname for SSL handshake
    ssl_socket.connect

    # Create driver socket with full URL
    socket = DriverSocket.new(ssl_socket, url)

    @socket = ssl_socket

    @driver = WebSocket::Driver.client(socket)

    # Set authentication headers
    @driver.set_header("Authorization", bearer_token)
    @driver.set_header("User-Agent", "appconfiguration-ruby-sdk/#{IbmAppconfigurationRubySdk::VERSION}")
    puts "✓ Headers set with authentication"

    register_callbacks

    @driver.start

    start_reader_thread

    # Start background retry if flag is set (fallback configurations were loaded)
    if @start_background_retry
      puts "🔄 Starting background retry (initial API fetch failed, using fallback config)"
      @background_retry_manager.start(
        reason: "Initial API fetch failed - using fallback configuration"
      )
    end
    @start_background_retry = true
  rescue StandardError => e
    puts "Connection failed: #{e.message}"

    transition_state(
      State::RECONNECTING
    )

    schedule_reconnect
  end

  def disconnect
    @should_reconnect = false

    transition_state(State::CLOSING)

    cleanup_connection

    transition_state(State::CLOSED)
  end

  def connected?
    @state == State::CONNECTED
  end

  # --------------------------------------------------
  # INTERNAL CALLBACKS
  # --------------------------------------------------

  def register_callbacks
    @driver.on(:open) do |event|
      puts "WebSocket connected"

      # Check for HTTP status code during WebSocket handshake
      # The event object may contain status_code for HTTP errors
      if event.respond_to?(:status_code) && event.status_code
        status_code = event.status_code

        # Check for client-side errors (4xx except 429 Too Many Requests)
        if status_code >= 400 && status_code < 500 && status_code != 429
          puts "❌ WebSocket handshake failed with client error: #{status_code}"
          puts "⛔ Client-side error detected - will not retry connection"
          @should_reconnect = false
          cleanup_connection
          transition_state(State::CLOSED)
          return
        end
      end

      transition_state(State::CONNECTED)

      @reconnect_attempts = 0

      @last_heartbeat_at = Time.now

      start_watchdog_thread
      start_connectivity_thread

      # Incase of websocket retry we need to call /config again
      @start_background_retry = true
    end

    @driver.on(:message) do |event|
      puts "Received: #{event.data}"

      if event.data == "test message"
        # Heartbeat message
        @last_heartbeat_at = Time.now
        puts "Heartbeat updated"
      else
        # Configuration update message
        puts "📦 Configuration update received"

        # Stop any active background retry and restart from t=0
        if @background_retry_manager.active?
          puts "🛑 Stopping active background retry to restart from t=0"
          @background_retry_manager.stop
        end

        # Start background retry manager which will fetch immediately at t=0
        puts "🔄 Starting background retry for configuration update..."
        @background_retry_manager.start(
          reason: "Configuration update notification received"
        )
        puts "✓ Background retry started (will fetch immediately at t=0)"
      end
    end

    @driver.on(:close) do |event|
      puts "Connection closed"

      puts "Code: #{event.code}"
      puts "Reason: #{event.reason}"

      # Check for WebSocket close codes that map to HTTP 4xx client errors
      # Close codes 4000-4499 (except 4429) indicate client-side errors
      if event.code && event.code >= 4000 && event.code < 4500 && event.code != 4429
        puts "❌ WebSocket closed with client error code: #{event.code}"
        puts "⛔ Client-side error detected - will not retry connection"
        @should_reconnect = false
        cleanup_connection
        transition_state(State::CLOSED)
        return
      end

      @should_reconnect = true
      handle_disconnect("WebSocket close")
    end

    @driver.on(:error) do |event|
      puts "WebSocket error"

      p event

      # Check if error contains a status code indicating client-side error
      if event.respond_to?(:status_code) && event.status_code
        status_code = event.status_code

        # Check for client-side errors (4xx except 429 Too Many Requests)
        if status_code >= 400 && status_code < 500 && status_code != 429
          puts "❌ WebSocket error with client error status: #{status_code}"
          puts "⛔ Client-side error detected - will not retry connection"
          @should_reconnect = false
          cleanup_connection
          transition_state(State::CLOSED)
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

          puts "Server disconnected"

          handle_disconnect("EOF")

        end
      rescue IOError => e
        if e.message.include?("stream closed")

          puts "Reader thread stopped"

        else

          puts "Reader IO error: #{e.message}"

          handle_disconnect(
            "Reader IO failure"
          )

        end
      rescue StandardError => e
        unless @shutting_down

          puts "Reader error: #{e.message}"

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
    watchdog = Watchdog.new(self)

    @watchdog_thread = watchdog.start
  end

  # --------------------------------------------------
  # CONNECTIVITY
  # --------------------------------------------------

  def start_connectivity_thread
    @connectivity_thread = Thread.new do
      is_connected = true

      loop do
        sleep(30)

        internet = Connectivity.check_internet

        if !internet

          puts "⚠️ No Internet Connection"

          is_connected = false

        else

          unless is_connected

            puts "✓ Internet connection restored"

            # Connection will be handled by reconnect logic
            handle_disconnect("Lost iinternet")

          end

          is_connected = true

        end
      end
    rescue StandardError => e
      puts "Connectivity thread error: #{e.message}"
    end
  end

  def handle_disconnect(reason)
    should_schedule = false

    @state_mutex.synchronize do
      return if [
        State::RECONNECTING,
        State::CLOSING,
        State::CLOSED
      ].include?(@state)

      puts "Handling disconnect: #{reason}"

      transition_state(
        State::RECONNECTING
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
    begin
      @driver&.close
    rescue StandardError
    end

    begin
      @socket&.close
    rescue StandardError
    end

    # begin
    #   @reader_thread&.kill
    # rescue
    @reader_thread.kill if @reader_thread && @reader_thread != Thread.current

    begin
      @watchdog_thread&.kill
    rescue StandardError
    end

    @connectivity_thread&.kill if @connectivity_thread && @connectivity_thread != Thread.current

    @driver = nil
    @socket = nil

    @reader_thread = nil
    @watchdog_thread = nil
    @connectivity_thread = nil
  end

  # --------------------------------------------------
  # RECONNECT
  # --------------------------------------------------

  def schedule_reconnect
    delay =
      RetryPolicy.next_delay(
        @reconnect_attempts
      )

    puts "Reconnect in #{delay.round(2)} sec"

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
    puts "#{@state} -> #{new_state}"

    @state = new_state
  end

  # --------------------------------------------------
  # SETUP
  # --------------------------------------------------

  private

  def setup_sdk
    # Configure UrlBuilder
    @url_builder = UrlBuilder.instance
    @url_builder.region = @region
    @url_builder.guid = @guid
    @url_builder.apikey = @apikey
    @url_builder.set_websocket_url(@collection_id, @environment_id)

    # Configure ApiManager
    ApiManager.set_authenticator

    # Initialize ConfigFetcher
    @config_fetcher = ConfigFetcher.new(
      collection_id: @collection_id,
      environment_id: @environment_id
    )

    # Initialize BackgroundRetryManager
    @background_retry_manager = BackgroundRetryManager.new(
      collection_id: @collection_id,
      environment_id: @environment_id
    )
  end
end
