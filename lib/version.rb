# fluent-plugin-oci-logging version 1.0.
#
# Copyright (c) 2021, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

# frozen_string_literal: true

require 'open3'

def number_of_commits
  tstamp = Time.now.utc.strftime('%Y%m%d%H%M%S').to_s
  cmd = 'git log --pretty=oneline | wc -l'
  stdout_str, stderr_str, status = Open3.capture3(cmd)
  status.success? ? stdout_str.strip() : "rc-#{tstamp}"
end

module OCILogging
  MAJOR=1
  MINOR=0
  PATCH=number_of_commits
  VERSION = ENV['OCI_LOGGING_GEM_VERSION'] || "#{MAJOR}.#{MINOR}.#{PATCH}"
end
