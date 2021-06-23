# fluent-plugin-oci-logging version 1.0.
#
# Copyright (c) 2021, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
#

# frozen_string_literal: true

require 'bundler'
require 'rake/testtask'
require 'rake/clean'
require 'rubocop/rake_task'

Rake.application.options.trace = true

CLOBBER.include(File.join('pkg', '*'),
                File.join('gems', '*'))

Bundler::GemHelper.install_tasks
Rake::Task["release"].clear  # guard against accidental release
RuboCop::RakeTask.new

Rake::TestTask.new(:test) do |t|
  # To run test for only one file (or file path pattern)
  #  $ bundle exec rake test TEST=test/test_specified_path.rb
  t.description = "Run #{File.basename(File.dirname(__FILE__))}'s test suite"
  t.libs.push('test')
  t.test_files = FileList['test/**/test_*.rb'].sort
  t.verbose = true
  t.warning = false
end

desc "Run #{File.basename(File.dirname(__FILE__))}'s test suite and generate coverage report"
task :coverage do
  ENV['SIMPLE_COV'] = 'true'
  Rake::Task[:test].invoke
end

task build: [:test] unless ENV['NOTEST']
task :default => [:test]
