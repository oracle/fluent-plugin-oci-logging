# fluent-plugin-oci-logging version 1.0.
#
# Copyright (c) 2021, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

# frozen_string_literal: true

require 'etc'
require 'securerandom'
require 'oci'

module Fluent
  module Plugin
    # Common utility methods
    module PublicLoggingUtils
      PUBLIC_CLIENT_SPEC_VERSION = '1.0'
      PUBLIC_LOGGING_PREFIX = 'com.oraclecloud.logging.custom.'

      ##
      # Build the wrapper for all the log entries to be sent to lumberjack.
      #
      # @return [OCI::LoggingClient::Models::PutLogsDetails] PutLogsDetails wrapper to be filled with log entries
      def get_put_logs_details_request
        request = OCI::Loggingingestion::Models::PutLogsDetails.new
        request.specversion = PUBLIC_CLIENT_SPEC_VERSION
        request
      end

      ##
      # Build the requests to be sent to the Lumberjack endpoint.
      #
      # @param [Time] time Fluentd event time (may be different from event's
      #                    timestamp)
      # @param [Hash] record The fluentd record.
      # @param [String] tagpath The fluentd path if populated.
      # @param [Hash] log_batches_map List of pre-existing log batch.
      # @param [String] sourceidentifier The fluentd contianing the source path.
      #
      # @return [Array] requests List of requests for Lumberjack's backend.
      def build_request(time, record, tagpath, log_batches_map, sourceidentifier)
        log = @log || Logger.new($stdout)
        content = flatten_hash(record)

        # create lumberjack request records
        logentry = ::OCI::Loggingingestion::Models::LogEntry.new
        logentry.time = Time.at(time).utc.strftime('%FT%T.%LZ')
        begin
          logentry.data = content.to_json
        rescue StandardError
          begin
            log.warn('ruby "to_json" expected UTF-8 encoding will retry parsing with forced encoding')
            # json requires UTF-8 encoding some logs may not follow that format so we need to fix that
            content = encode_to_utf8(content)
            logentry.data = content.to_json
          rescue StandardError
            log.warn('unexpected encoding in the log request, will send log as a string instead of json')
            # instead of loosing data because of an unknown encoding issue send the data as a string
            logentry.data = content.to_s
          end
        end
        logentry.id = SecureRandom.uuid

        requestkey = tagpath + sourceidentifier

        unless log_batches_map.key?(requestkey)
          log_entry_batch = OCI::Loggingingestion::Models::LogEntryBatch.new
          log_entry_batch.source = @hostname
          log_entry_batch.type = PUBLIC_LOGGING_PREFIX + tagpath
          log_entry_batch.subject = sourceidentifier
          log_entry_batch.defaultlogentrytime = Time.at(time).utc.strftime('%FT%T.%LZ')
          log_entry_batch.entries = []

          log_batches_map[requestkey] = log_entry_batch
        end

        log_batches_map[requestkey].entries << logentry
      end

      ##
      # Send prebuilt requests to the logging endpoint.
      #
      # @param [Hash] log_batches_map
      def send_requests(log_batches_map)
        log = @log || Logger.new($stdout) # for testing

        request = get_put_logs_details_request

        request.log_entry_batches = log_batches_map.values
        begin
          resp = @client.put_logs(@log_object_id, request)
        rescue OCI::Errors::ServiceError => e
          log.error "Service Error received sending request: #{e}"
          if e.status_code == 400
            log.info 'Eating service error as it is caused by Bad Request[400 HTTP code]'
          else
            log.error "Throwing service error for status code:#{e.status_code} as we want fluentd to re-try"
            raise
          end
        rescue OCI::Errors::NetworkError => e
          log.error "Network Error received sending request: #{e}"
          if e.code == 400
            log.info 'Eating network error as it is caused by Bad Request[400 HTTP code]'
          else
            log.error "Throwing network error for code:#{e.code} as we want fluentd to re-try"
            raise
          end
        rescue StandardError => e
          log.error "Standard Error received sending request: #{e}"
          raise
        end
        request.log_entry_batches.each do |batch|
          log.info "log batch type #{batch.type}, log batch subject #{batch.subject}, size #{batch.entries.size}"
        end

        log.info "response #{resp.status} id: #{resp.request_id}"
      end

      ##
      # Flatten the keys of a hash.
      #
      # @param [Hash] record The hash object to flatten.
      #
      # @return [Hash] The updated, flattened, hash.
      def flatten_hash(record)
        record.each_with_object({}) do |(k, v), h|
          if v.is_a? Hash
            flatten_hash(v).map { |h_k, h_v| h["#{k}.#{h_k}"] = h_v }
          elsif k == 'log'
            h['msg'] = v
          else
            h[k] = v
          end
        end
      end

      ##
      # Force all the string values in the hash to be encoded to UTF-8.
      #
      # @param [Hash] record the flattened hash needing to have the encoding changes
      #
      # @return [Hash] The updated hash.
      def encode_to_utf8(record)
        # the reason for using ISO-8859-1 is that it covers most of the out
        # of band characters other encoding's don't have this way we can
        # encode it to a known value and then encode it back into UTF-8
        record.transform_values { |v| v.to_s.force_encoding('ISO-8859-1').encode('UTF-8') }
      end

      ##
      # Parse out the log_type from the chunk metadata tag
      #
      # @param [String] rawtag the string of the chunk metadata tag that needs to be parsed
      #
      # @return [String] take out the tag after the first '.' character or return the whole tag if there is no '.'
      def get_modified_tag(rawtag)
        tag = rawtag || 'empty'
        tag.split('.').length > 1 ? tag.partition('.')[2] : tag
      end

      ##
      # Return the correct oci configuration file path for linux platforms.
      #
      # @return [String] path to the configuration file
      def self.determine_linux_config_path
        managed_agent = '/etc/unified-monitoring-agent/.oci/config'
        unmanaged_agent = File.join(Dir.home, '.oci/config')
        config = File.file?(managed_agent) ? managed_agent : unmanage_agent
        return config
      rescue StandardError
        return unmanaged_agent
      end

      ##
      # Return the correct oci configuration file path for windows platforms.
      #
      # @return [String] path to the configuration file
      def self.determine_windows_config_path
        managed_agent = 'C:\\oracle_unified_agent\\.oci\\config'
        unmanaged_agent = File.join("C:\\Users\\#{Etc.getlogin}\\.oci\\config")
        config = File.file?(managed_agent) ? managed_agent : unmanage_agent
        return config
      rescue StandardError
        return unmanaged_agent
      end

      ##
      # Return the correct oci configuration user profile for auth
      #
      # @param [String] linux_cfg Path to linux configuration file
      # @param [String] windows_cfg Path to windows configuration file
      #
      # @return [String] username to use
      def self.determine_config_profile_name(linux_cfg, windows_cfg)
        managed_agent='UNIFIED_MONITORING_AGENT'
        unmanaged_agent='DEFAULT'
        location = OS.windows? ? windows_cfg : linux_cfg
        if location.start_with?('/etc/unified-monitoring-agent',  'C:\\oracle_unified_agent')
          return managed_agent
        end
        oci_config = OCI::ConfigFileLoader.load_config(config_file_location: location)
        oci_config.profile
      rescue StandardError
        unmanaged_agent
      end
    end
  end
end
