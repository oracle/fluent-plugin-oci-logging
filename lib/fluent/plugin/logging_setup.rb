# fluent-plugin-oci-logging version 1.0.
#
# Copyright (c) 2021, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

# frozen_string_literal: true

require 'retriable'
require 'oci'

require_relative 'os'
require_relative 'logging_utils'

module Fluent
  module Plugin
    # Setup code for OCI Logging
    module PublicLoggingSetup
      RETRIES = 3
      USER_SIGNER_TYPE = 'user'
      AUTO_SIGNER_TYPE = 'auto'
      LINUX_OCI_CONFIG_DIR = Fluent::Plugin::PublicLoggingUtils.determine_linux_config_path
      WINDOWS_OCI_CONFIG_DIR = Fluent::Plugin::PublicLoggingUtils.determine_windows_config_path
      USER_CONFIG_PROFILE_NAME = Fluent::Plugin::PublicLoggingUtils.determine_config_profile_name(LINUX_OCI_CONFIG_DIR, WINDOWS_OCI_CONFIG_DIR)
      PUBLIC_RESOURCE_PRINCIPAL_ENV_FILE = '/etc/resource_principal_env'

      R1_CA_PATH = '/etc/pki/tls/certs/ca-bundle.crt'
      PUBLIC_DEFAULT_LINUX_CA_PATH = '/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem'
      PUBLIC_DEFAULT_WINDOWS_CA_PATH = 'C:\\oracle_unified_agent\\unified-monitoring-agent\\embedded\\ssl\\certs\\cacert.pem'
      PUBLIC_DEFAULT_UBUNTU_CA_PATH = '/etc/ssl/certs/ca-certificates.crt'

      def logger
        @log ||= OS.windows? ? Logger.new(WINDOWS_UPLOADER_OUTPUT_LOG) : Logger.new($stdout)
      end

      ##
      # Calculate federation endpoints based on metadata and optional inputs
      #
      # @param [String] region the region identifier
      #
      # @return [String] the federation endpoint that will be used
      def get_federation_endpoint(region)
        if region == 'r1'
          endpoint = ENV['FEDERATION_ENDPOINT'] || 'https://auth.r1.oracleiaas.com/v1/x509'
        else
          if @realmDomainComponent.nil?
            logger.warn('realm domain is null, fall back to OCI Regions')
            @realmDomainComponent = OCI::Regions.get_second_level_domain(region) if @realmDomainComponent.nil?
          end

          endpoint = ENV['FEDERATION_ENDPOINT'] || "https://auth.#{region}.#{@realmDomainComponent}/v1/x509"
        end

        logger.info("endpoint is #{endpoint} in region #{region}")
        endpoint
      end

      def get_instance_md_with_retry(retries = RETRIES)
        Retriable.retriable(tries: retries, on: StandardError, timeout: 12) do
          return get_instance_md
        end
      end

      def get_instance_md
        # v2 of IMDS requires an authorization header
        md = get_instance_md_with_url('http://169.254.169.254/opc/v2/instance/')
        if md.nil?
          logger.info('IMDS v2 is not available, use v1')
          md = get_instance_md_with_url('http://169.254.169.254/opc/v1/instance/')
        end

        if !md.nil?
          logger.info "Successfully fetch instance metadata for hosts in overlay #{md}"
          return md
        else
          raise StandardError, 'Failure fetching instance metadata, possible '\
            'reason is network issue or host is not OCI instance'
        end
      end

      def get_instance_md_with_url(uri_link)
        uri = URI.parse(uri_link)
        http = ::Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 2 # in seconds
        http.read_timeout = 2 # in seconds
        request = ::Net::HTTP::Get.new(uri.request_uri)
        request.add_field('Authorization', 'Bearer Oracle') if uri_link.include?('v2')
        resp = http.request(request)
        JSON.parse(resp.body)
      rescue StandardError
        logger.warn("failed to get instance metadata with link #{uri_link}")
        nil
      end

      ##
      # Calculate logging endpoint from environment or metadata.
      # Preference is given to the environment variable 'LOGGING_FRONTEND'.
      #
      # @param [String] region the region identifier
      #
      # @return [String] The logging endpoint that will be used.
      def get_logging_endpoint(region, logging_endpoint_override: nil)
        unless logging_endpoint_override.nil?
          logger.info "using logging endpoint override #{logging_endpoint_override} for testing"
          return logging_endpoint_override
        end

        if region == 'r1'
          endpoint = ENV['LOGGING_FRONTEND'] || "https://ingestion.logging.#{region}.oci.oracleiaas.com"
        else
          if @realmDomainComponent.nil?
            logger.warn('realm domain is null, fall back to OCI Regions')
            @realmDomainComponent = OCI::Regions.get_second_level_domain(region) if @realmDomainComponent.nil?
          end

          endpoint = ENV['LOGGING_FRONTEND'] || "https://ingestion.logging.#{region}.oci.#{@realmDomainComponent}"
        end

        logger.info("endpoint is #{endpoint} in region #{region}")
        endpoint
      end

      def get_signer_type(principal_override: nil, config_dir: nil)
        config_dir ||= OS.windows? ?  WINDOWS_OCI_CONFIG_DIR : LINUX_OCI_CONFIG_DIR

        if (File.file?(config_dir) && principal_override != AUTO_SIGNER_TYPE) || principal_override == USER_SIGNER_TYPE
          begin
            logger.info("using #{USER_SIGNER_TYPE} signer type with config dir #{config_dir}")
            oci_config = OCI::ConfigFileLoader.load_config(
              config_file_location: config_dir, profile_name: USER_CONFIG_PROFILE_NAME
            )
            signer_type = USER_SIGNER_TYPE
          rescue StandardError => e
            if e.full_message.include?('Profile not found in the given config file.')
              logger.warn("Profile #{USER_CONFIG_PROFILE_NAME} not configured "\
                "in user api-key cli using other principal instead: #{e}")
              signer_type = AUTO_SIGNER_TYPE
              oci_config = OCI::Config.new
            else
              raise "User api-keys not setup correctly: #{e}"
            end
          end
        else # if user api-keys is not setup in the expected format we expect instance principal
          logger.info("using #{AUTO_SIGNER_TYPE} signer type")
          signer_type = AUTO_SIGNER_TYPE
          oci_config = OCI::Config.new
        end
        [oci_config, signer_type]
      end

      ##
      # Configure the signer for the logging client call
      #
      # @param [String] signer_type the type of signer that should be returned
      #
      # @return [OCI::Signer] a signer that is representative of the signer type
      def get_signer(oci_config, signer_type)
        case signer_type
        when USER_SIGNER_TYPE
          get_host_info_for_non_oci_instance(oci_config)
          set_default_ca_file
          OCI::Signer.new(
            oci_config.user,
            oci_config.fingerprint,
            oci_config.tenancy,
            oci_config.key_file,
            pass_phrase: oci_config.pass_phrase
          )
        when AUTO_SIGNER_TYPE
          logger.info 'signer type is "auto", creating signer based on system setup'
          get_host_info_for_oci_instance
          set_default_ca_file
          signer = create_resource_principal_signer
          if signer.nil?
            logger.info('resource principal is not setup, use instance principal instead')
            signer = create_instance_principal_signer
          else
            logger.info('use resource principal')
          end

          signer
        else
          raise StandardError, "Principal type #{signer_type} not supported, "\
            "use 'instance', 'resource' or 'user' instead"
        end
      end

      def get_host_info_for_non_oci_instance(oci_config)
        # set needed properties
        @region = oci_config.region
        # for non-OCI instances we can't get the display_name or hostname from IMDS and the fallback is the ip address
        # of the machine
        begin
          @hostname = Socket.gethostname
        rescue StandardError
          ip = Socket.ip_address_list.detect { |intf| intf.ipv4_private? }
          @hostname = ip ? ip.ip_address : 'UNKNOWN'
        end

        # No metadata service support for non-OCI instances
        @realmDomainComponent = OCI::Regions.get_second_level_domain(@region)

        logger.info("in non oci instance, region is #{@region}, "\
                    " hostname is #{@hostname}, realm is #{@realmDomainComponent}")
      end

      def get_host_info_for_oci_instance
        md = @metadata_override || get_instance_md_with_retry

        @region = md['canonicalRegionName'] == 'us-seattle-1' ? 'r1' : md['canonicalRegionName']
        @hostname = md.key?('displayName') ? md['displayName'] : ''
        @realmDomainComponent = md.fetch('regionInfo', {}).fetch(
          'realmDomainComponent', OCI::Regions.get_second_level_domain(@region)
        )
        logger.info("in oci instance, region is #{@region},  hostname is"\
          " #{@hostname}, realm is #{@realmDomainComponent}")
      end

      ##
      # Since r1 overlay has a different default make sure to update this
      #
      def set_default_ca_file
        if OS.windows?
          @ca_file = @ca_file == PUBLIC_DEFAULT_LINUX_CA_PATH ? PUBLIC_DEFAULT_WINDOWS_CA_PATH : @ca_file
        elsif OS.ubuntu?
          @ca_file = @ca_file == PUBLIC_DEFAULT_LINUX_CA_PATH ? PUBLIC_DEFAULT_UBUNTU_CA_PATH : @ca_file
        else
          @ca_file = @region == 'r1' && @ca_file == PUBLIC_DEFAULT_LINUX_CA_PATH ? R1_CA_PATH : @ca_file
        end

        if @ca_file.nil?
          msg = 'ca_file is not specified'
          logger.error msg
          raise StandardError, msg
        end

        # verify the ssl bundle actually exists
        unless File.file?(@ca_file)
          msg = "Does not exist or cannot open ca file: #{@ca_file}"
          logger.error msg
          raise StandardError, msg
        end

        # setting the cert_bundle_path
        logger.info "using cert_bundle_path #{@ca_file}"
      end

      def create_resource_principal_signer
        logger.info 'creating resource principal'
        add_rp_env_override
        OCI::Auth::Signers.resource_principals_signer
      rescue StandardError => e
        logger.info("fail to create resource principal with error #{e}")
        nil
      end

      def add_rp_env_override
        env_file = ENV['LOCAL_TEST_ENV_FILE'] || PUBLIC_RESOURCE_PRINCIPAL_ENV_FILE

        resource_principal_env = {}

        raise 'resource principal env file does not exist' unless File.exist? env_file

        file = File.readlines(env_file)
        file.each do |env|
          a = env.split('=')
          resource_principal_env[a[0]] = a[1].chomp
        end

        logger.info("resource principal env is setup with #{resource_principal_env}")
        ENV.update resource_principal_env
      end

      def create_instance_principal_signer
        endpoint = @federation_endpoint_override || get_federation_endpoint(@region)

        unless endpoint.nil?
          logger.info "create instance principal with  federation_endpoint = #{endpoint}, cert_bundle #{@ca_file}"
        end

        ::OCI::Auth::Signers::InstancePrincipalsSecurityTokenSigner.new(
          federation_endpoint: endpoint, federation_client_cert_bundle: @ca_file
        )
      end
    end
  end
end
