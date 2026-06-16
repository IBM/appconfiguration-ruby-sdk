# Examples

This folder contains sample applications demonstrating how to use the IBM Cloud App Configuration Ruby SDK.

## Running app.rb

The `app.rb` file demonstrates how to use the SDK to evaluate feature flags in a continuous loop.

### Prerequisites

1. Install the SDK dependencies from the root directory:
   ```bash
   bundle install
   ```

2. Set up your App Configuration service credentials. You'll need:
   - Region (e.g., `us-south`, `eu-gb`)
   - GUID (Instance ID from service credentials)
   - API Key (from service credentials)
   - Collection ID (from Collections section)
   - Environment ID (from Environments section)

### Steps to run

1. Open `app.rb` and uncomment the configuration constants at the top of the file (lines 8-12), then add your credentials:
   ```ruby
   REGION = 'us-south'  # Your region
   GUID = 'your-guid'   # Your instance GUID
   APIKEY = 'your-apikey'  # Your API key
   COLLECTION_ID = 'your-collection-id'  # Your collection ID
   ENVIRONMENT_ID = 'your-environment-id'  # Your environment ID
   ```

2. Update the feature ID in the example (line 64) to match a feature flag in your App Configuration instance:
   ```ruby
   feature = client.get_feature('your-feature-id')
   ```

3. Run the example:
   ```bash
   ruby examples/app.rb
   ```

The application will continuously evaluate the feature flag and display statistics showing enabled and disabled evaluations. Press `Ctrl+C` to stop the application.

### Optional configurations

The example also demonstrates:
- **Bootstrap file mode**: Uncomment lines 32-35 and comment out lines 24-30 to run offline using a bootstrap configuration file
- **Entity attributes**: Modify the `entity_attributes` hash (lines 59-61) to test segment targeting
- **Failure simulation**: Uncomment the failure simulation blocks (lines 79-89) to test error handling

### What the example does

The application:
1. Initializes the App Configuration SDK with your credentials
2. Continuously generates random user IDs
3. Evaluates a feature flag for each user
4. Tracks and displays statistics of enabled vs disabled evaluations
5. Demonstrates real-time feature flag evaluation with entity attributes