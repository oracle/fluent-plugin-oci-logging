# fluent-plugin-oci-logging version 1.0.
#
# Copyright (c) 2021, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

# frozen_string_literal: true

require_relative 'logging_utils'
require_relative 'logging_setup'
require 'socket'

module Fluent
  module Plugin
    # OCI Logging Fluentd Output plugin
    class OCILoggingOutput < Fluent::Plugin::Output
      include Fluent::Plugin::PublicLoggingUtils
      include Fluent::Plugin::PublicLoggingSetup

      Fluent::Plugin.register_output('oci_logging', self)

      # allow instance metadata to be configurable (for testing)
      config_param :metadata_override, :hash, default: nil

      # Path to the PEM CA certificate file for TLS. Can contain several CA certs.
      # We are defaulting to '/etc/oci-pki/ca-bundle.pem'
      # This can be overriden for testing.
      config_param :ca_file, :string, default: PUBLIC_DEFAULT_LINUX_CA_PATH

      # Override to manually provide the host endpoint
      config_param :logging_endpoint_override, :string, default: nil

      # Override to manually provide the federation endpoint
      config_param :federation_endpoint_override, :string, default: nil

      # The only required parameter used to identify where we are sending logs for LJ
      config_param :log_object_id, :string

      # optional forced override for debugging, testing, and potential custom configurations
      config_param :principal_override, :string, default: nil

      attr_accessor :client, :hostname

      helpers :event_emitter

      PAYLOAD_SIZE = 9*1024*1024 #restricting payload size at 9MB

      def configure(conf)
        super
        log.debug 'determining the signer type'

        oci_config, signer_type = get_signer_type(principal_override: @principal_override)
        signer = get_signer(oci_config, signer_type)
        log.info "using authentication principal #{signer_type}"

        @client = OCI::Loggingingestion::LoggingClient.new(
          config: oci_config,
          endpoint: get_logging_endpoint(@region, logging_endpoint_override: @logging_endpoint_override),
          signer: signer,
          proxy_settings: nil,
          retry_config: nil
        )

        @client.api_client.request_option_overrides = { ca_file: @ca_file }
      end

      def start
        super
        log.debug 'start'
      end

      #### Sync Buffered Output ##############################
      # Implement write() if your plugin uses a normal buffer.
      ########################################################
      def write(chunk)
        log.debug "writing chunk metadata #{chunk.metadata}", \
                  dump_unique_id_hex(chunk.unique_id)
        log_batches_map = {}
        # For standard chunk format (without #format() method) 
        size = 0 
        chunk.each do |time, record|
          begin
            tag = get_modified_tag(chunk.metadata.tag)
            source_identifier = record.key?('tailed_path') ? record['tailed_path'] : ''
            content = flatten_hash(record)
            size += content.to_json.bytesize
            build_request(time, record, tag, log_batches_map, source_identifier)
            if size >= PAYLOAD_SIZE
              log.info "Exceeding payload size. Size : #{size}"
              send_requests(log_batches_map)
              log_batches_map = {}
              size = 0
            end
          rescue StandardError => e
            log.error(e.full_message)
          end
        end
        # flushing data to LJ
        unless log_batches_map.empty?
          log.info "Payload size : #{size}"
          send_requests(log_batches_map)
        end
      end
    end
  end
end
