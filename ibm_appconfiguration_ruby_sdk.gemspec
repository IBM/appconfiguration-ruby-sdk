# frozen_string_literal: true

require_relative "lib/ibm_appconfiguration_ruby_sdk/version"

Gem::Specification.new do |spec|
  spec.name = "ibm_appconfiguration_ruby_sdk"
  spec.version = IbmAppconfigurationRubySdk::VERSION
  spec.authors = ["IBM Cloud App Configuration"]
  spec.email = ["mdevsrvs@in.ibm.com"]

  spec.summary = "IBM Cloud App Configuration Ruby SDK"
  spec.description = "IBM Cloud App Configuration SDK is used to perform feature evaluation based on the configuration on IBM Cloud App Configuration service."
  spec.homepage = "https://github.com/IBM/appconfiguration-ruby-sdk"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/IBM/appconfiguration-ruby-sdk"
  spec.metadata["changelog_uri"] = "https://github.com/IBM/appconfiguration-ruby-sdk/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/IBM/appconfiguration-ruby-sdk/issues"
  spec.metadata["documentation_uri"] = "https://github.com/IBM/appconfiguration-ruby-sdk"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .github/ .rubocop.yml .cra/ .whitesource .secrets.baseline
                          .pre-commit-config.yaml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_runtime_dependency "ibm_cloud_sdk_core", "~> 1.1"
  spec.add_runtime_dependency "json", "~> 2.0"
  spec.add_runtime_dependency "murmurhash3", "~> 0.1"
  spec.add_runtime_dependency "websocket-driver", "~> 0.7"

  # Development dependencies
  spec.add_development_dependency "irb"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "yard", "~> 0.9"
end
