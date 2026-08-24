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

##
# This file defines the various constants used by the SDK.
#
module IbmAppconfigurationRubySdk
module Constants
  # Maximum number of retries for API requests
  MAX_NUMBER_OF_RETRIES = 3

  # HTTP Status codes
  STATUS_CODE_OK = 200
  STATUS_CODE_ACCEPTED = 202

  # Socket constants
  CUSTOM_SOCKET_CLOSE_REASON_CODE = 4001
  SOCKET_CONNECTION_ERROR = "Socket connection error"
  SOCKET_LOST_ERROR = "Socket connection lost"
  SOCKET_CONNECTION_CLOSE = "Socket connection is closed"
  SOCKET_INCOMING_DATA = "Received data from socket"
  SOCKET_MESSAGE_RECEIVED = "Message received from server"
  SOCKET_CALLBACK = "Message passed to handler"
  SOCKET_MESSAGE_ERROR = "Message received from server is invalid"
  SOCKET_CONNECTION_SUCCESS = "Successfully connected to App Configuration server"
  APPCONFIGURATION_CLIENT_EMITTER = "configurationUpdate"

  # Error messages
  REGION_ERROR = "Provide a valid region in App Configuration init"
  GUID_ERROR = "Provide a valid guid in App Configuration init"
  APIKEY_ERROR = "Provide a valid apiKey in App Configuration init"
  COLLECTION_ID_VALUE_ERROR = "Provide a valid collectionId in App Configuration setContext method."
  ENVIRONMENT_ID_VALUE_ERROR = "Provide a valid environmentId in App Configuration setContext method."
  COLLECTION_ID_ERROR = "Invalid action in App Configuration. This action can be performed only after a successful initialization."
  COLLECTION_INIT_ERROR = "Invalid action in App Configuration. This action can be performed only after a successful initialization and setting the context."
  INVALID_OPTIONS_PARAMETER = "options param passed to setContext is invalid. Should be a Hash"
  CONFIGURATION_FILE_NOT_FOUND_ERROR = "bootstrapFile parameter should be provided while liveConfigUpdateEnabled is false during initialization."
  PERSISTENT_CACHE_OPTION_ERROR = "setContext: [options.persistentCacheDirectory]. Invalid value -"
  BOOTSTRAP_FILEPATH_OPTION_ERROR = "setContext: [options.bootstrapFile]. Invalid value -"
  LIVE_CONFIG_UPDATE_OPTION_ERROR = "setContext: [options.liveConfigUpdateEnabled]. Invalid value -"
  BOOTSTRAP_FILEPATH_NOT_FOUND_ERROR = "setContext: [options.bootstrapFile] parameter should be provided when [options.liveConfigUpdateEnabled] is false."
  NO_INTERNET_CONNECTION_ERROR = "Check for network connectivity failed. Re-checking..."
  INVALID_ENTITY_ID = "Invalid entityId passed to"
  SINGLETON_EXCEPTION = "Initialize object first"

  # Default values
  DEFAULT_SEGMENT_ID = "$$null$$"
  DEFAULT_ENTITY_ID = "$$null$$"
  DEFAULT_USAGE_LIMIT = 30
  DEFAULT_ROLLOUT_PERCENTAGE = "$default"
  DEFAULT_FEATURE_VALUE = "$default"
  DEFAULT_PROPERTY_VALUE = "$default"

  # Secret Manager
  INVALID_SECRET_MANAGER_CLIENT_MESSAGE = "Secret Manager object passed to getSecret method is null or undefined."
  SECRETREF = "SECRETREF"

  # Success messages
  SUCCESSFULLY_FETCHED_THE_CONFIGURATIONS = "Successfully fetched the configurations"
  SUCCESSFULLY_POSTED_METERING_DATA = "Successfully posted metering data"
  SUCCESSFULLY_POSTED_EXPERIMENT_EVALUATION_EVENTS = "Successfully posted evaluation events"
  SUCCESSFULLY_POSTED_EXPERIMENT_METRIC_EVENTS = "Successfully posted metric events"

  # Error messages for posting data
  ERROR_POSTING_METERING_DATA = "Error while posting metering data"
  ERROR_POSTING_EXPERIMENT_EVALUATION_EVENTS = "Error while posting evaluation events"
  ERROR_POSTING_EXPERIMENT_METRIC_EVENTS = "Error while posting metric events"
  ERROR_NO_WRITE_PERMISSION = "Persistent cache directory provided doesn't have write permission. Make sure the directory has required access."
  INPUT_PARAMETER_NOT_BOOLEAN = "Input parameter passed to usePrivateEndpoint() method is not boolean. Default value will be used."

  # Rollout types
  MANUAL = "MANUAL"
  PROGRESSIVE = "PROGRESSIVE"

  # Delimiter
  DELIMITER = "\u001F"

  # WebSocket / connection log messages
  WEBSOCKET_INITIATING_CONNECTION      = "Initiating websocket connection to the App Configuration server..."
  WEBSOCKET_AUTH_TOKEN_FAILED          = "Failed to get authentication token"
  WEBSOCKET_AUTH_TOKEN_SUCCESS         = "Successfully obtained authentication token for websocket connection"
  WEBSOCKET_URL_FAILED                 = "Failed to get WebSocket URL"
  WEBSOCKET_REQUEST_SENT               = "Websocket connection request sent to the App Configuration server"
  WEBSOCKET_CONNECTED                  = "WebSocket connected"
  WEBSOCKET_CONNECTION_RESET_WATCHDOG  = "Connection successful, Reset the retries and start watchdog"
  WEBSOCKET_ESTABLISHED                = "Successfully established websocket connection with App Configuration server."
  WEBSOCKET_ON_CLOSE                   = "On connection close"
  WEBSOCKET_ON_ERROR                   = "On connection error"
  WEBSOCKET_SERVER_DISCONNECTED        = "Server disconnected"
  WEBSOCKET_READER_THREAD_STOPPED      = "Reader thread stopped"
  WEBSOCKET_NO_INTERNET                = "No internet connection"
  WEBSOCKET_INTERNET_RESTORED          = "Internet connection restored"
  WEBSOCKET_HEARTBEAT_UPDATED          = "Heartbeat updated"
  WEBSOCKET_CONFIG_UPDATE_RECEIVED     = "Configuration update received"
  WEBSOCKET_BACKGROUND_RETRY_STARTED   = "Background retry started"
  WEBSOCKET_CONNECTION_LOST               = "WebSocket connection to App Configuration server lost"
  WEBSOCKET_CLOSING_EXISTING              = "Closing existing websocket connection"
  WEBSOCKET_STARTING_BACKGROUND_RETRY     = "Starting background retry (initial API fetch failed, using fallback config)"
  WEBSOCKET_STOP_ACTIVE_BACKGROUND_RETRY  = "Stopping active background retry to restart from t=0"

  # Watchdog log messages
  WATCHDOG_NOT_RUNNING     = "Watchdog is not running"
  WATCHDOG_STOPPING        = "Stopping Watchdog timer"

  # BackgroundRetryManager log messages
  BACKGROUND_RETRY_INITIALIZED   = "BackgroundRetryManager initialized"
  BACKGROUND_RETRY_STOPPED       = "Background retry stopped"
  BACKGROUND_RETRY_CONFIGS_OK    = "Configurations fetched successfully"

  # ConfigFetcher log messages
  CONFIG_API_CALL_SUCCESS            = "API call successful (200)"
  CONFIG_PROCESSING_RESPONSE         = "Processing API response..."
  CONFIG_EXTRACTED_SUCCESSFULLY      = "Configurations extracted successfully"
  CONFIG_PROCESSED_AND_LOADED        = "Configurations processed and loaded successfully"
  CONFIG_LOAD_FAILED                 = "Failed to load configurations to cache"
  CONFIG_LOADING_TO_CACHE            = "Loading configurations to ConfigurationHandler cache..."
  CONFIG_LOADED_TO_CACHE             = "Configurations loaded to cache successfully"

  # ConfigurationHandler log messages
  CONFIG_LOADED_SUCCESSFULLY            = "Configurations loaded successfully"
  CONFIG_STARTING_WEBSOCKET             = "Starting WebSocket client for live updates"
  CONFIG_WEBSOCKET_STARTED              = "WebSocket client started successfully"
  CONFIG_UPDATE_LISTENER_REGISTERED     = "Configuration update listener registered"
  CONFIG_UPDATE_LISTENER_NO_BLOCK       = "No block provided to register_configuration_update_listener"
  CONFIG_UPDATE_NOTIFYING_LISTENER      = "Notifying configuration update listener"
  CONFIG_LIVE_UPDATE_ENABLED              = "Live update enabled - fetching configurations from API..."
  CONFIG_NO_CONFIGURATIONS_AVAILABLE     = "No configurations available - neither from API nor from cache/bootstrap"

  # FileManager log messages
  PERSISTENT_CACHE_FILE_NOT_FOUND = "configuration file in the persistent cache doesn't exist"
  PERSISTENT_CACHE_FILE_EMPTY     = "configuration file in the persistent cache is empty"

  # ApiManager log messages
  IAM_TOKEN_OBTAINED = "Token obtained"
end
end
