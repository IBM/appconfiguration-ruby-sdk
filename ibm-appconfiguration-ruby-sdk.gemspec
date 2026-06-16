# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'version'

Gem::Specification.new do |spec|
  spec.name          = 'ibm-appconfiguration-ruby-sdk'
  spec.version       = IBMAppConfiguration::VERSION
  spec.authors       = ['IBM Cloud App Configuration']
  spec.email         = ['mdevsrvs@in.ibm.com']

  spec.summary       = 'IBM Cloud App Configuration Ruby SDK'
  spec.description   = 'IBM Cloud App Configuration SDK is used to perform feature evaluation based on the configuration on IBM Cloud App Configuration service.'
  spec.homepage      = 'https://github.com/IBM/appconfiguration-ruby-sdk'
  spec.license       = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/IBM/appconfiguration-ruby-sdk'
  spec.metadata['changelog_uri'] = 'https://github.com/IBM/appconfiguration-ruby-sdk/blob/main/CHANGELOG.md'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/IBM/appconfiguration-ruby-sdk/issues'
  spec.metadata['documentation_uri'] = 'https://github.com/IBM/appconfiguration-ruby-sdk'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob('{lib}/**/*') + %w[README.md Gemfile]
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_runtime_dependency 'ibm_cloud_sdk_core', '~> 1.1'
  spec.add_runtime_dependency 'json', '~> 2.0'
  spec.add_runtime_dependency 'murmurhash3', '~> 0.1'
  spec.add_runtime_dependency 'websocket-driver', '~> 0.7'

  # Development dependencies
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'yard', '~> 0.9'
end

