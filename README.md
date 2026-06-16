# IBM Cloud App Configuration Ruby SDK

IBM Cloud App Configuration SDK is used to perform feature flag and property evaluation and track custom metrics for Experimentation based on the configuration on IBM Cloud App Configuration service.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Import the SDK](#import-the-sdk)
- [Usage](#usage)
- [Adding URLs to your allowlist](#adding-urls-to-your-allowlist)
- [License](#license)

## Overview

IBM Cloud App Configuration is a centralized feature management and configuration service
on [IBM Cloud](https://www.cloud.ibm.com) for use with web and mobile applications, microservices, and distributed
environments.

Instrument your applications with App Configuration Ruby SDK, and use the App Configuration dashboard, CLI or API to
define feature flags or properties, organized into collections and targeted to segments. Toggle feature flag states in
the cloud to activate or deactivate features in your application or environment, when required. Run experiments and measure the effect of feature flags on end users by tracking custom metrics. You can also manage the properties for distributed applications centrally.

## Installation

Installation is done using the `gem install` command or by adding it to your Gemfile.

```bash
gem install ibm_appconfiguration_ruby_sdk
```

Or add this line to your application's Gemfile:

```ruby
gem 'ibm_appconfiguration_ruby_sdk'
```

And then execute:

```bash
bundle install
```

## Import the SDK

To import the module:

```ruby
require 'ibm_appconfiguration_ruby_sdk'
```

## Usage

Initialize the SDK to connect with your App Configuration service instance.

```ruby
require 'ibm_appconfiguration_ruby_sdk'

# Get the singleton instance
app_config_client = IbmAppconfigurationRubySdk::AppConfiguration.instance

region = 'us-south'
guid = '<guid>'
apikey = '<apikey>'
collection_id = 'airlines-webapp'
environment_id = 'dev'

# Enable debug logging (optional)
app_config_client.set_debug(true)

# Initialize the SDK
app_config_client.init(region, guid, apikey)

# Set context
app_config_client.set_context(collection_id, environment_id)
```

> :warning: It is expected that initialization to be done **only once**.

After the SDK is initialized successfully, the feature flags & properties can be retrieved using the `app_config_client` as shown in the below code snippet.

<details><summary>Expand to view the example snippet</summary>

```ruby
# Get feature
feature = app_config_client.get_feature('online-check-in')
if feature
  result = feature.get_current_value(entity_id, entity_attributes)
  puts result
end

# Get property
property = app_config_client.get_property('check-in-charges')
if property
  result = property.get_current_value(entity_id, entity_attributes)
  puts result
end
```
</details>

where,
- **region**: Region name where the App Configuration service instance is created. 
See list of supported locations [here](https://cloud.ibm.com/catalog/services/app-configuration). Eg:- `us-south`, `au-syd`, `eu-gb`, `us-east`, `eu-de`, `ca-tor`, `jp-tok`, `jp-osa` etc.
- **guid**: Instance Id of the App Configuration service. Obtain it from the service credentials section of the App
  Configuration dashboard.
- **apikey**: ApiKey of the App Configuration service. Obtain it from the service credentials section of the App
  Configuration dashboard.
- **collection_id**: Id of the collection created in App Configuration service instance under the **Collections** section.
- **environment_id**: Id of the environment created in App Configuration service instance under the **Environments** section.

### Connect using private network connection (optional)

Set the SDK to connect to App Configuration service by using a private endpoint that is accessible only through the IBM Cloud private network.

```ruby
app_config_client.use_private_endpoint(true)
```

This must be done before calling the `init` method on the SDK.

### (Optional)

In order for your application and SDK to continue its operations even during the unlikely scenario of App Configuration service across your application restarts, you can configure the SDK to work using a persistent cache. The SDK uses the persistent cache to store the App Configuration data that will be available across your application restarts.

```ruby
app_config_client.set_context(collection_id, environment_id, {
  persistent_cache_directory: '/var/lib/docker/volumes/'
})
```

* **persistent_cache_directory**: Absolute path to a directory which has read & write permission for the user. The SDK will create a file - `appconfiguration.json` in the specified directory, and it will be used as the persistent cache to store the App Configuration service information.

When persistent cache is enabled, the SDK will keep the last known good configuration at the persistent cache. In the case of App Configuration server being unreachable, the latest configurations at the persistent cache is loaded to the application to continue working.

Please ensure that the cache file is not lost or deleted in any case. For example, consider the case when a kubernetes pod is restarted and the cache file (appconfiguration.json) was stored in ephemeral volume of the pod. As pod gets restarted, kubernetes destroys the ephemeral volume in the pod, as a result the cache file gets deleted. So, make sure that the cache file created by the SDK is always stored in persistent volume by providing the correct absolute path of the persistent directory.

### (Optional)

The SDK is also designed to serve configurations, perform feature flag & property evaluations without being connected to App Configuration service.

```ruby
app_config_client.set_context(collection_id, environment_id, {
  bootstrap_file: 'saflights/flights.json',
  live_config_update_enabled: false
})
```

This usecase will throw error if given `bootstrap_file` is not found or if unable to parse the json coming from the bootstrap file.

* **bootstrap_file**: Absolute path of the JSON file, which contains configuration details. Make sure to provide a proper JSON file. You can generate this file using `ibmcloud ac export` command of the IBM Cloud App Configuration CLI.
* **live_config_update_enabled**: Live configuration update from the server. Set this value to `false` if the new configuration values shouldn't be fetched from the server.

## Get single feature

```ruby
feature = app_config_client.get_feature('online-check-in') # feature can be nil in case of an invalid feature id

if feature
  puts "Feature Name: #{feature.get_feature_name}"
  puts "Feature Id: #{feature.get_feature_id}"
  puts "Feature Type: #{feature.get_feature_data_type}"
  if feature.is_enabled?
    # feature flag is enabled
  else
    # feature flag is disabled
  end
end
```

## Get all features

```ruby
features = app_config_client.get_features
feature = features['online-check-in']

if feature
  puts "Feature Name: #{feature.get_feature_name}"
  puts "Feature Id: #{feature.get_feature_id}"
  puts "Feature Type: #{feature.get_feature_data_type}"
  puts "Is feature enabled? #{feature.is_enabled?}"
end
```

## Evaluate a feature

Use the `feature.get_current_value(entity_id, entity_attributes)` method to evaluate the value of the feature flag. This method returns a Hash containing evaluated value, feature flag enabled status & evaluation details.

```ruby
entity_id = 'john_doe'
entity_attributes = {
  city: 'Bangalore',
  country: 'India'
}

result = feature.get_current_value(entity_id, entity_attributes)
puts result[:value] # Evaluated value of the feature flag. The type of evaluated value will match the type of feature flag (Boolean, String, Numeric).
puts result[:is_enabled] # enabled status.
puts result[:details] # a Hash containing detailed information of the evaluation. See below

# the `result[:details]` will have the following
puts result[:details][:value_type] # a string value. Example: DISABLED_VALUE
puts result[:details][:reason] # a string value. Example: Disabled value of the feature flag since the feature flag is disabled.
puts result[:details][:segment_name] # (only if applicable, else it is nil) a string value containing the segment name for which the feature flag was evaluated.
puts result[:details][:rollout_percentage_applied] # (only if applicable, else it is nil) a boolean value. True if the entity_id was part of the rollout percentage evaluation, false otherwise.
puts result[:details][:error_type] # (only if applicable, else it is nil) contains the error message if any error occurred during the evaluation.
```

- **entity_id**: Id of the Entity. This will be a string identifier related to the Entity against which the feature is evaluated. For example, an entity might be an instance of an app that runs on a mobile device, a microservice that runs on the cloud, or a component of infrastructure that runs that microservice. For any entity to interact with App Configuration, it must provide a unique entity ID.
- **entity_attributes**: A Hash consisting of the attribute name and their values that defines the specified entity. This is an optional parameter if the feature flag is not configured with any targeting definition. If the targeting is configured, then entity_attributes should be provided for the rule evaluation. An attribute is a parameter that is used to define a segment. The SDK uses the attribute values to determine if the specified entity satisfies the targeting rules, and returns the appropriate feature flag value.

## Send custom metrics

Record custom metrics for experiments using the track method. Calling track will queue the metric event, which will be sent in batches to the App Configuration servers.

```ruby
app_config_client.track(event_key, entity_id)
```

where
- **event_key**: The event key for the metric associated with the running experiment. The event key in your metric and the event key in your code must match exactly.

## Get single property

```ruby
property = app_config_client.get_property('check-in-charges') # property can be nil in case of an invalid property id

if property
  puts "Property Name: #{property.get_property_name}"
  puts "Property Id: #{property.get_property_id}"
  puts "Property Type: #{property.get_property_data_type}"
end
```

## Get all properties

```ruby
properties = app_config_client.get_properties
property = properties['check-in-charges']

if property
  puts "Property Name: #{property.get_property_name}"
  puts "Property Id: #{property.get_property_id}"
  puts "Property Type: #{property.get_property_data_type}"
end
```

## Evaluate a property

Use the `property.get_current_value(entity_id, entity_attributes)` method to evaluate the value of the property. This method returns a Hash containing evaluated value & evaluation details.

```ruby
entity_id = 'john_doe'
entity_attributes = {
  city: 'Bangalore',
  country: 'India'
}

result = property.get_current_value(entity_id, entity_attributes)
puts result[:value] # Evaluated value of the property. The type of evaluated value will match the type of property (Boolean, String, Numeric).
puts result[:details] # a Hash containing detailed information of the evaluation. See below

# the `result[:details]` will have the following
puts result[:details][:value_type] # a string value. Example: DEFAULT_VALUE
puts result[:details][:reason] # a string value. Example: Default value of the property.
puts result[:details][:segment_name] # (only if applicable, else it is nil) a string value containing the segment name for which the property was evaluated.
puts result[:details][:error_type] # (only if applicable, else it is nil) contains the error message if any error occurred during the evaluation.
```

- **entity_id**: Id of the Entity. This will be a string identifier related to the Entity against which the property is evaluated. For example, an entity might be an instance of an app that runs on a mobile device, a microservice that runs on the cloud, or a component of infrastructure that runs that microservice. For any entity to interact with App Configuration, it must provide a unique entity ID.
- **entity_attributes**: A Hash consisting of the attribute name and their values that defines the specified entity. This is an optional parameter if the property is not configured with any targeting definition. If the targeting is configured, then entity_attributes should be provided for the rule evaluation. An attribute is a parameter that is used to define a segment. The SDK uses the attribute values to determine if the specified entity satisfies the targeting rules, and returns the appropriate property value.

## Get secret property

Explicit method for getting the secret references stored in App Configuration.

```ruby
secret_property_object = app_config_client.get_secret(property_id, secrets_manager_service)
```

- **property_id**: property_id is the unique string identifier, using this we will be able to fetch the property which will provide the necessary metadata to fetch the secret.
- **secrets_manager_service**: an initialized secrets manager client, which will be used for getting the secret data during the secret property evaluation. Create a secret manager client by referring the doc: https://cloud.ibm.com/apidocs/secrets-manager/secrets-manager-v2?code=ruby#authentication

## Evaluate a secret property

Use the `secret_property_object.get_current_value(entity_id, entity_attributes)` method to evaluate the value of the secret property.

Note that the output of this method call is different from `get_current_value` invoked using feature & property objects. This method returns the actual secret value of the evaluated secret reference. The response contains the secret data from the Secrets Manager.

```ruby
entity_id = 'john_doe'
entity_attributes = {
  city: 'Bangalore',
  country: 'India'
}

begin
  response = secret_property_object.get_current_value(entity_id, entity_attributes)
  # See below to know how to access the secret data from the response
rescue StandardError => e
  # handle the error
end
```

## How to access the secret data from a successful response

<details><summary>Full example:</summary>

```ruby
require 'ibm_appconfiguration_ruby_sdk'
require 'ibm_secrets_manager_sdk'

app_config_client = IbmAppconfigurationRubySdk::AppConfiguration.instance

begin
  app_config_client.init(region, guid, apikey)
  app_config_client.set_context(collection_id, environment_id)
rescue StandardError => e
  puts "Failed to initialize app configuration sdk: #{e}"
end

# Initialize Secrets Manager client
authenticator = IbmCloudSdkCore::Authenticators::IamAuthenticator.new(
  apikey: '<SECRETS_MANAGER_APIKEY>'
)

secrets_manager_service = IbmCloudSecretsManagerApiV2::SecretsManagerV2.new(
  authenticator: authenticator
)
secrets_manager_service.service_url = '<SECRETS_MANAGER_INSTANCE_URL>'

begin
  secret_property_object = app_config_client.get_secret(property_id, secrets_manager_service)
  response = secret_property_object.get_current_value(entity_id, entity_attributes)

  # For Arbitrary secret type
  puts response.result['payload']

  # For username-password secret type
  puts response.result['username']
  puts response.result['password']

  # For key-value secret type
  puts response.result['data']['key1']
  puts response.result['data']['key2']
rescue StandardError => e
  # handle the error
  puts "Error: #{e}"
end
```
</details>

## Fetching the app_config_client across other modules

Once the SDK is initialized, the app_config_client can be obtained across other modules as shown below:

```ruby
# **other modules**

require 'ibm_appconfiguration_ruby_sdk'

app_config_client = IbmAppconfigurationRubySdk::AppConfiguration.instance

feature = app_config_client.get_feature('online-check-in')
enabled = feature.is_enabled?
result = feature.get_current_value(entity_id, entity_attributes)
```

## Supported Data types

App Configuration service allows to configure the feature flag and properties in the following data types: Boolean,
Numeric, SecretRef, String. The String data type can be of the format of a text string, JSON or YAML. The SDK processes each
format accordingly as shown in the below table.

<details><summary>View Table</summary>

| **Feature or Property value**                                                                          | **DataType** | **DataFormat** | **Type of data returned <br> by `get_current_value[:value]`** | **Example output**                                                   |
| ------------------------------------------------------------------------------------------------------ | ------------ | -------------- | ----------------------------------------------------- | -------------------------------------------------------------------- |
| `true`                                                                                                 | BOOLEAN      | not applicable | `Boolean`                                                | `true`                                                               |
| `25`                                                                                                   | NUMERIC      | not applicable | `Numeric`                                             | `25`                                                                 |
| "a string text"                                                                                        | STRING       | TEXT           | `String`                                              | `"a string text"`                                                      |
| <pre>{<br>  "firefox": {<br>    "name": "Firefox",<br>    "pref_url": "about:config"<br>  }<br>}</pre> | STRING       | JSON           | `Hash`                              | `{"firefox"=>{"name"=>"Firefox","pref_url"=>"about:config"}}` |
| <pre>men:<br>  - John Smith<br>  - Bill Jones<br>women:<br>  - Mary Smith<br>  - Susan Williams</pre>  | STRING       | YAML           | `String`                              | `"men:\n  - John Smith\n  - Bill Jones\nwomen:\n  - Mary Smith\n  - Susan Williams"` |

For property of type secret reference, refer to readme section [evaluate-a-secret-property](#evaluate-a-secret-property)
</details>

<details><summary>Feature flag</summary>

```ruby
feature = app_config_client.get_feature('json-feature')
feature.get_feature_data_type # STRING
feature.get_feature_data_format # JSON

# Example (traversing the returned Hash)
result = feature.get_current_value(entity_id, entity_attributes)
puts result[:value]['key'] # prints the value of the key

feature = app_config_client.get_feature('yaml-feature')
feature.get_feature_data_type # STRING
feature.get_feature_data_format # YAML
feature.get_current_value(entity_id, entity_attributes)
```
</details>

<details><summary>Property</summary>

```ruby
property = app_config_client.get_property('json-property')
property.get_property_data_type # STRING
property.get_property_data_format # JSON

# Example (traversing the returned Hash)
result = property.get_current_value(entity_id, entity_attributes)
puts result[:value]['key'] # prints the value of the key

property = app_config_client.get_property('yaml-property')
property.get_property_data_type # STRING
property.get_property_data_format # YAML
property.get_current_value(entity_id, entity_attributes)
```
</details>

## Set listener for feature and property data changes

The SDK provides a callback mechanism to notify you in real-time when feature flag's or property's configuration changes. You can register a configuration update listener using the same app_config_client.

```ruby
app_config_client.register_configuration_update_listener do
  # **add your code**
  # To find the effect of any configuration changes, you can call the feature or property related methods

  # feature = app_config_client.get_feature('online-check-in')
  # new_result = feature.get_current_value(entity_id, entity_attributes)
end
```

## Enable debugger (optional)

Use this method to enable/disable the logging in SDK.

```ruby
app_config_client.set_debug(true)
```

## Examples

Try [this](./examples) sample application in the examples folder to learn more about feature and property evaluation.

## Adding URLs to your allowlist

This SDK requires connectivity to the internet (if bootstrap based initialization is not done). The endpoints listed below should be reachable from the host/infrastructure where this SDK will run.

```
https://cloud.ibm.com:443
https://iam.cloud.ibm.com:443
https://{region}.apprapp.cloud.ibm.com:443
wss://{region}.apprapp.cloud.ibm.com:443
```

If opted for private endpoint by setting `app_config_client.use_private_endpoint(true)` then the allowlist will be

```
https://cloud.ibm.com:443
https://private.iam.cloud.ibm.com:443
https://private.{region}.apprapp.cloud.ibm.com:443
wss://private.{region}.apprapp.cloud.ibm.com:443
```

where `region` is the region where your App Configuration service instance is provisioned such as `us-south`, `us-east`, `eu-gb`, `au-syd`, `eu-de`, `ca-tor`, `jp-tok`, `jp-osa` etc.

## License

This project is released under the Apache 2.0 license. The license's full text can be found
in [LICENSE](https://github.com/IBM/appconfiguration-ruby-sdk/blob/master/LICENSE)