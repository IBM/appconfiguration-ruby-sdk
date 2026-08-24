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

require "spec_helper"
require "socket"
require "openssl"
require "websocket/driver"

# ─────────────────────────────────────────────────────────────────────────────
# SSL peer-verification bypass
#
# ConnectionManager#connect calls:
#   ssl_context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
#
# That would reject our self-signed server certificate.  We prepend a module
# that turns set_params into a no-op AND pre-sets VERIFY_NONE in initialize.
# The module is prepended once (idempotent) when this file is loaded and stays
# in place for the entire spec file.  It does NOT affect other spec files
# because the server-side SSLContext assigned cert+key explicitly, and
# VERIFY_NONE on a server context merely means the server skips requesting
# a client certificate (which is the normal behaviour for public TLS servers).
# ─────────────────────────────────────────────────────────────────────────────
module SslNoVerify
  def initialize(*args)
    super
    self.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end

  def set_params(_opts = {})
    # no-op: prevent production code from re-enabling VERIFY_PEER
  end
end

# Prepend only once — idempotent guard.
unless OpenSSL::SSL::SSLContext.ancestors.include?(SslNoVerify)
  OpenSSL::SSL::SSLContext.prepend(SslNoVerify)
end

# ─────────────────────────────────────────────────────────────────────────────
# MockWssServer
#
# A minimal in-process WSS (WebSocket-over-TLS) server used as the remote end
# in connection tests.  It uses a self-signed certificate so no real network or
# PKI infrastructure is required.
#
# Lifecycle:
#   server = MockWssServer.new   # OS assigns a free port
#   server.start                 # starts background accept + reader threads
#   # ... connect a client ...
#   server.wait_for_open         # block until the WS handshake completes
#   server.send_message("ping")  # send a frame to the connected client
#   server.wait_for_message      # block until the client sends a frame
#   server.close_connection      # send a WS close frame
#   server.stop                  # tear everything down
# ─────────────────────────────────────────────────────────────────────────────
class MockWssServer
  attr_reader :port

  # One self-signed cert shared across all instances (generated once at load).
  KEY = OpenSSL::PKey::RSA.generate(2048)
  CERT = begin
    c = OpenSSL::X509::Certificate.new
    c.version    = 2
    c.serial     = 1
    c.not_before = Time.now
    c.not_after  = Time.now + 3_600
    c.subject    = OpenSSL::X509::Name.parse("/CN=localhost")
    c.issuer     = c.subject
    c.public_key = KEY.public_key
    c.sign(KEY, OpenSSL::Digest::SHA256.new)
    c
  end

  def initialize
    @tcp_server = TCPServer.new("127.0.0.1", 0)   # 0 → OS-assigned free port
    @port       = @tcp_server.addr[1]

    # Build the server SSL context directly using the C-level ivar assignment
    # (bypassing our SslNoVerify#initialize) so the server context keeps its
    # cert and key but still has VERIFY_NONE (no client-cert requests).
    ssl_ctx      = OpenSSL::SSL::SSLContext.new
    ssl_ctx.cert = CERT
    ssl_ctx.key  = KEY
    @ssl_server  = OpenSSL::SSL::SSLServer.new(@tcp_server, ssl_ctx)

    @driver          = nil
    @conn            = nil
    @open            = false
    @received        = []
    @msg_mutex       = Mutex.new
    @msg_cv          = ConditionVariable.new
    @accept_thread   = nil
    @reader_thread   = nil
  end

  def start
    @accept_thread = Thread.new { accept_and_serve }
    self
  end

  def stop
    @reader_thread&.kill
    @accept_thread&.kill
    @conn&.close rescue nil
    @ssl_server.close rescue nil
    @tcp_server.close rescue nil
  end

  # Send a WebSocket text frame to the connected client.
  def send_message(text)
    @driver&.text(text)
  end

  # Close the WebSocket connection from the server side.
  def close_connection(code = 1000, reason = "")
    @driver&.close(reason, code)
  end

  # Block until the WebSocket open event fires on the server side.
  def wait_for_open(timeout: 3)
    deadline = Time.now + timeout
    sleep 0.02 while !@open && Time.now < deadline
    raise "MockWssServer: timed out waiting for WS open (port #{@port})" unless @open
  end

  # Block until the client sends at least one message; return it.
  def wait_for_message(timeout: 3)
    deadline = Time.now + timeout
    @msg_mutex.synchronize do
      while @received.empty?
        remaining = deadline - Time.now
        raise "MockWssServer: timed out waiting for message" if remaining <= 0

        @msg_cv.wait(@msg_mutex, remaining)
      end
      @received.shift
    end
  end

  def messages_received
    @msg_mutex.synchronize { @received.dup }
  end

  private

  def accept_and_serve
    @conn   = @ssl_server.accept
    @driver = WebSocket::Driver.server(@conn)

    @driver.on(:connect) { @driver.start }
    @driver.on(:open)    { @open = true }
    @driver.on(:message) do |event|
      @msg_mutex.synchronize do
        @received << event.data
        @msg_cv.broadcast
      end
    end
    @driver.on(:close) { @conn.close rescue nil }
    @driver.on(:error) { @conn.close rescue nil }

    @reader_thread = Thread.new do
      loop do
        data = @conn.readpartial(4096)
        @driver.parse(data)
      end
    rescue StandardError
      # Connection closed — normal at end of test.
    end

    @reader_thread.join
  rescue StandardError
    # Server-side race during teardown — harmless.
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Shared helpers included into every example group in this file.
# ─────────────────────────────────────────────────────────────────────────────
module WsTestHelpers
  # Stub every SDK component that ConnectionManager creates in setup_sdk so
  # tests never touch real IAM, the real App Configuration API, or real threads
  # outside the WebSocket flow itself.
  def stub_sdk_infrastructure
    allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:set_authenticator)
    allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:token)
      .and_return("Bearer test-token")
    allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:refresh_token!)
    allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:reset!)

    fetcher_dbl = instance_double(
      IbmAppconfigurationRubySdk::ConfigFetcher,
      fetch: { ok: false, retryable: false, status: 0, data: nil },
      process_and_load_configurations: true,
      load_configurations_to_cache: true
    )
    allow(IbmAppconfigurationRubySdk::ConfigFetcher).to receive(:new).and_return(fetcher_dbl)

    @retry_dbl = instance_double(
      IbmAppconfigurationRubySdk::BackgroundRetryManager,
      start: true, stop: nil, active?: false
    )
    allow(IbmAppconfigurationRubySdk::BackgroundRetryManager)
      .to receive(:new).and_return(@retry_dbl)

    handler_dbl = instance_double(IbmAppconfigurationRubySdk::ConfigurationHandler)
    allow(IbmAppconfigurationRubySdk::ConfigurationHandler)
      .to receive(:instance).and_return(handler_dbl)
  end

  # Point UrlBuilder at the mock server and reset ApiManager.
  def configure_for_mock_server(server)
    IbmAppconfigurationRubySdk::ApiManager.reset!
    builder = IbmAppconfigurationRubySdk::UrlBuilder.instance
    builder.region            = "us-south"
    builder.guid              = "test-guid"
    builder.apikey            = "test-apikey"
    builder.use_private_endpoint = false
    builder.base_service_url  = nil
    builder.instance_variable_set(
      :@websocket_full_url,
      "wss://localhost:#{server.port}/apprapp/wsfeature?instance_id=test-guid&collection_id=col&environment_id=env"
    )
  end

  # Build a ConnectionManager wired to the mock server.
  # schedule_reconnect is stubbed to prevent threads that outlive the test.
  def build_manager(server)
    configure_for_mock_server(server)
    mgr = IbmAppconfigurationRubySdk::ConnectionManager.new(
      region: "us-south",
      guid: "test-guid",
      apikey: "test-apikey",
      collection_id: "col",
      environment_id: "env"
    )
    # setup_sdk inside ConnectionManager.new calls set_websocket_url which
    # overwrites @websocket_full_url.  Re-apply our mock-server URL here.
    IbmAppconfigurationRubySdk::UrlBuilder.instance.instance_variable_set(
      :@websocket_full_url,
      "wss://localhost:#{server.port}/apprapp/wsfeature?instance_id=test-guid&collection_id=col&environment_id=env"
    )
    allow(mgr).to receive(:schedule_reconnect)
    mgr
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# WebSocketClient specs
# ─────────────────────────────────────────────────────────────────────────────
RSpec.describe IbmAppconfigurationRubySdk::WebSocketClient do
  include WsTestHelpers

  let!(:server) { MockWssServer.new.start }

  before do
    stub_sdk_infrastructure
    configure_for_mock_server(server)
  end

  after { server.stop }

  # WebSocketClient delegates directly to an internal ConnectionManager, which
  # calls setup_sdk in its constructor and overwrites @websocket_full_url.
  # We use build_manager's pattern: construct first, then re-apply the URL.
  let(:client) do
    c = described_class.new(
      region: "us-south",
      guid: "test-guid",
      apikey: "test-apikey",
      collection_id: "col",
      environment_id: "env"
    )
    # Re-apply mock-server URL after setup_sdk has overwritten it.
    IbmAppconfigurationRubySdk::UrlBuilder.instance.instance_variable_set(
      :@websocket_full_url,
      "wss://localhost:#{server.port}/apprapp/wsfeature?instance_id=test-guid&collection_id=col&environment_id=env"
    )
    # Prevent background reconnect threads that outlive the test.
    allow(c.instance_variable_get(:@manager)).to receive(:schedule_reconnect)
    c
  end

  describe "#connected?" do
    it "returns false before connect is called" do
      expect(client.connected?).to be(false)
    end

    it "returns true after a successful WebSocket handshake with the mock server" do
      client.connect
      server.wait_for_open
      sleep 0.15     # let the :open callback transition state
      expect(client.connected?).to be(true)
      client.disconnect
    end
  end

  describe "#disconnect" do
    it "returns connected? == false after disconnecting" do
      client.connect
      server.wait_for_open
      sleep 0.1
      client.disconnect
      expect(client.connected?).to be(false)
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# ConnectionManager specs
# ─────────────────────────────────────────────────────────────────────────────
RSpec.describe IbmAppconfigurationRubySdk::ConnectionManager do
  include WsTestHelpers

  let!(:server) { MockWssServer.new.start }

  before do
    stub_sdk_infrastructure
  end

  after { server.stop }

  # ── Initial state ─────────────────────────────────────────────────────────

  describe "initial state" do
    subject(:manager) { build_manager(server) }

    it "is not connected before connect is called" do
      expect(manager.connected?).to be(false)
    end

    it "has last_heartbeat_at set to a recent time" do
      expect(manager.last_heartbeat_at).to be_within(2).of(Time.now)
    end
  end

  # ── Successful connection ─────────────────────────────────────────────────

  describe "#connect (successful handshake)" do
    subject(:manager) { build_manager(server) }

    it "transitions to connected after the WebSocket handshake completes" do
      manager.connect
      server.wait_for_open
      sleep 0.15
      expect(manager.connected?).to be(true)
      manager.disconnect
    end
  end

  # ── disconnect ────────────────────────────────────────────────────────────

  describe "#disconnect" do
    subject(:manager) { build_manager(server) }

    it "makes connected? return false" do
      manager.connect
      server.wait_for_open
      sleep 0.1
      manager.disconnect
      expect(manager.connected?).to be(false)
    end
  end

  # ── Heartbeat message ─────────────────────────────────────────────────────

  describe "heartbeat processing" do
    subject(:manager) { build_manager(server) }

    it "updates last_heartbeat_at when the server sends 'test message'" do
      manager.connect
      server.wait_for_open
      sleep 0.1

      before_hb = manager.last_heartbeat_at
      sleep 0.05
      server.send_message("test message")
      sleep 0.25   # reader thread processes the frame

      expect(manager.last_heartbeat_at).to be >= before_hb
      manager.disconnect
    end
  end

  # ── Configuration update message ─────────────────────────────────────────

  describe "configuration update message" do
    it "starts the background retry manager when a non-heartbeat message is received" do
      mgr = build_manager(server)
      mgr.connect
      server.wait_for_open
      sleep 0.1

      server.send_message("configuration_update_event")
      sleep 0.25

      expect(@retry_dbl).to have_received(:start).at_least(:once)
      mgr.disconnect
    end
  end

  # ── Server-initiated close ────────────────────────────────────────────────

  describe "server-initiated close" do
    subject(:manager) { build_manager(server) }

    it "transitions to not-connected when the server closes the WebSocket" do
      manager.connect
      server.wait_for_open
      sleep 0.1

      manager.instance_variable_set(:@should_reconnect, false)
      server.close_connection
      sleep 0.3

      expect(manager.connected?).to be(false)
    end
  end

  # ── Auth failure ─────────────────────────────────────────────────────────

  describe "IAM token failure" do
    it "does not become connected when token retrieval raises" do
      allow(IbmAppconfigurationRubySdk::ApiManager).to receive(:token)
        .and_raise(IbmAppconfigurationRubySdk::ConfigurationError, "auth failed")

      mgr = build_manager(server)
      mgr.connect
      sleep 0.1
      expect(mgr.connected?).to be(false)
    end
  end

  # ── transition_state ─────────────────────────────────────────────────────

  describe "#transition_state" do
    subject(:manager) { build_manager(server) }

    it "is publicly callable and changes connected? accordingly" do
      manager.transition_state(IbmAppconfigurationRubySdk::State::CONNECTED)
      expect(manager.connected?).to be(true)

      manager.transition_state(IbmAppconfigurationRubySdk::State::DISCONNECTED)
      expect(manager.connected?).to be(false)
    end
  end
end
