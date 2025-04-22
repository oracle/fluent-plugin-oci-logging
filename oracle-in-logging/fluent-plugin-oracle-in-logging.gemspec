# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name    = "fluent-plugin-oracle-in-logging"
  spec.version = ENV['FLUENT_GEM_VERSION'] || '0.0.0'
  spec.authors = ['Unified Agent team']
  spec.email   = ['no-reply@support.oracle.com']

  spec.summary       = %q{A Fluentd input plugin for fetching logs from Oracle Cloud Infrastructure Logging.}
  spec.description   = %q{This plugin provides an input source to fetch and collect logs from Oracle Cloud Infrastructure's logging service. It supports filtering logs by log groups, log objects, and custom search queries}
  spec.homepage      = "https://github.com/your-repo/fluent-plugin-oracle-in-logging"
  spec.license       = "Apache-2.0"
  
  files                      = Dir.glob('lib/**/*') + ['README.md'].select { |fn| File.file?(fn) }
  spec.files                 = files
  spec.executables           = files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths         = ['lib']
  spec.required_ruby_version = '>= 2.6'

  # Development dependencies
  spec.add_development_dependency 'rake', "~> 13.1.0"

  spec.add_runtime_dependency 'fluentd', ">= 1.16.0"
  spec.add_runtime_dependency 'oci'
  spec.add_runtime_dependency 'retriable', ">= 2.0.0"
end
