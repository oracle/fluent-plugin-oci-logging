# fluent-plugin-oci-logging version 1.0.
#
# Copyright (c) 2021, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
#

# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require_relative 'lib/version'

Gem::Specification.new do |spec|
  spec.name          = 'fluent-plugin-oci-logging'
  spec.version       = OCILogging::VERSION
  spec.authors       = ['OCI Observability Team']
  spec.email         = ['no-reply@support.oracle.com']
  spec.homepage      = 'https://docs.cloud.oracle.com/en-us/iaas/Content/Logging/Concepts/loggingoverview.htm'
  spec.licenses      = ['UPL-1.0', 'Apache-2.0']
  files              = Dir.glob("lib/**/**").select { |fn| File.file?(fn) }
  spec.files         = files
  spec.executables   = files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.extra_rdoc_files = ['README.md']

  spec.summary       = 'OCI Fluentd Logging output plugin following Unified Schema'
  spec.description   = 'Oracle Observability FluentD Plugins : Logging output plugin for OCI logging'

  spec.add_runtime_dependency 'fluentd', '~> 1.12.3'
  spec.add_runtime_dependency 'oci', '~> 2.12'
  spec.add_runtime_dependency 'retriable', '~> 3.1.2'

  spec.add_development_dependency 'bundler', '> 1.0'
  spec.add_development_dependency 'mocha', '~> 1.9'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rubocop-rake', '~> 0.5'
  spec.add_development_dependency 'simplecov', '~> 0.17'
  spec.add_development_dependency 'test-unit', '~> 3.0'
  spec.add_development_dependency 'webmock', '~> 3.0'
end
