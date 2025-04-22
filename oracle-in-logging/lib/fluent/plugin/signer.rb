# Copyright (c) 2024, Oracle and/or its affiliates.

require 'retriable'
require "fluent/plugin/input"
require 'oci'

module Fluent
  module Plugin
    module Signer
      RETRIES = 3
      USER_SIGNER_TYPE = "user"
      INSTANCE_SIGNER_TYPE = "instance"
      RESOURCE_SIGNER_TYPE = "resource"
      WORKLOAD_SIGNER_TYPE = "workload_identity"
      USER_CONFIG_PROFILE_NAME = "ORACLE_IN_LOGGING"
      OCI_CONFIG_DIR = "/etc/oracle-in-logging/.oci/config"
      RESOURCE_PRINCIPAL_ENV_FILE = "/etc/resource_principal_env"

      R1_CA_PATH='/etc/pki/tls/certs/ca-bundle.crt'
      PUBLIC_DEFAULT_LINUX_CA_PATH = "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"

      REGION_REALM_MAPPING = {
        'us-phoenix-1': 'oc1'.freeze
      }
      REALM_DOMAIN_MAPPING = {
        'oc1': 'oraclecloud.com'.freeze
      }

      def get_oci_config(principal)
        log.debug "determining the signer type"

        if principal['@type'] == USER_SIGNER_TYPE
          begin
            config_dir = principal['oci_config_path'] || OCI_CONFIG_DIR
            profile = principal['oci_config_profile'] || USER_CONFIG_PROFILE_NAME

            log.info("using #{profile} in config #{config_dir}")

            oci_config = OCI::ConfigFileLoader.load_config(config_file_location: config_dir, profile_name: profile)
          rescue => error
            if error.full_message.include?("Profile not found in the given config file.")
              raise "Profile #{profile} not found. Please configure the profile through the OCI CLI or in the OCI config file to proceed further"
            else
              raise "User profile not setup correctly: #{error}"
            end
          end
        else
          oci_config = OCI::Config.new
        end
        return oci_config
      end

      ##
      # Configure the signer for the logging client call
      #
      # @param [String] signer_type the type of signer that should be returned
      #
      # @return [OCI::Signer] a signer that is representative of the signer type
      def get_signer(oci_config, principal)
        if principal['@type'] == USER_SIGNER_TYPE
          log.info "signer type is #{USER_SIGNER_TYPE}"
          get_host_info_for_user_principal(oci_config)
          set_default_ca_file
          signer = OCI::Signer.new(
              oci_config.user,
              oci_config.fingerprint,
              oci_config.tenancy,
              oci_config.key_file,
              pass_phrase: oci_config.pass_phrase)
          signer
        elsif principal['@type'] == WORKLOAD_SIGNER_TYPE
          log.info "signer type is #{WORKLOAD_SIGNER_TYPE}"
          signer = OCI::Auth::Signers.oke_workload_resource_principal_signer
          signer

        elsif principal['@type'] == INSTANCE_SIGNER_TYPE
          log.info "signer type is #{INSTANCE_SIGNER_TYPE}, creating signer based on system setup"
          get_host_info
          set_default_ca_file
          signer = create_instance_principal_signer
          signer

        elsif principal['@type'] == RESOURCE_SIGNER_TYPE
          log.info "signer type is #{RESOURCE_SIGNER_TYPE}, creating signer based on system setup"
          get_host_info
          set_default_ca_file
          rp_env = principal['resource_principal_env_file'] || RESOURCE_PRINCIPAL_ENV_FILE
          signer = create_resource_principal_signer(rp_env)
          signer
        else
          raise StandardError.new("Principal type #{principal['@type']} not supported, use 'instance', 'resource', 'user' or 'workload_identity' instead")
        end
      end

      def create_instance_principal_signer
        endpoint = get_federation_endpoint(@region)

        log.info "Create instance principal with federation_endpoint = #{endpoint}, cert_bundle #{@ca_file}" unless endpoint.nil?
        ::OCI::Auth::Signers::InstancePrincipalsSecurityTokenSigner.new(
            federation_endpoint: endpoint,  federation_client_cert_bundle: @ca_file)
      end

      def get_host_info_for_user_principal(oci_config)
        # set needed properties
        @region = oci_config.region
        # for non-OCI instances we can't get the display_name or hostname from IMDS and the fallback is the ip address
        # of the machine
        begin
          @hostname = Socket.gethostname
        rescue
          ip = Socket.ip_address_list.detect{|intf| intf.ipv4_private?}
          @hostname = ip ? ip.ip_address : 'UNKNOWN'
        end

        # No metadata service support for non-OCI instances
        log.info("If user principal is used, try getting domain from local map first")
        @realmDomainComponent = getLocalRealmDomainComponent(@region)
        if @realmDomainComponent.nil?
          #OCI library in turn uses metadata and will default to OC1 realm if no metadata is found
          @realmDomainComponent = OCI::Regions.get_second_level_domain(@region)
        end

        log.info("In the instance, region is #{@region}, hostname is #{@hostname}, realm is #{@realmDomainComponent}")
      end

      ##
      # Since r1 overlay has a different default make sure to update this
      #
      def set_default_ca_file
        @ca_file = PUBLIC_DEFAULT_LINUX_CA_PATH if @ca_file.nil?
        if @region == 'r1' && @ca_file == PUBLIC_DEFAULT_LINUX_CA_PATH
          @ca_file = R1_CA_PATH
        end
        # verify the ssl bundle actually exists
        unless File.file?(@ca_file)
          msg = "Does not exist or cannot open ca file: #{@ca_file}"
          log.error msg
          raise StandardError, msg
        end

        # setting the cert_bundle_path
        log.info "Using cert_bundle_path #{@ca_file}"
      end

      def getLocalRealmDomainComponent(region)
        return nil if region.nil?
        symbolised_region = region.to_sym
        if REGION_REALM_MAPPING.key?(symbolised_region)
          realm = REGION_REALM_MAPPING[symbolised_region]
        else
          return nil
        end

        # return second level domain if exists
        symbolised_realm = realm.to_sym
        return REALM_DOMAIN_MAPPING[symbolised_realm] if REALM_DOMAIN_MAPPING.key?(symbolised_realm)
      end

      def get_host_info
        md = get_instance_md_with_retry

        @region = md['canonicalRegionName'] == 'us-seattle-1' ? 'r1' : md['canonicalRegionName']
        @hostname = md.key?('displayName') ? md['displayName'] : ''
        @realmDomainComponent = md.fetch('regionInfo', Hash.new).fetch('realmDomainComponent', OCI::Regions.get_second_level_domain(@region))
        log.info("In oci instance, region is #{@region}, hostname is #{@hostname}, realm is #{@realmDomainComponent}")
      end

      def create_resource_principal_signer(rp_env)
        begin
          log.info 'creating resource principal'
          add_rp_env_override(rp_env)
          OCI::Auth::Signers.resource_principals_signer
        rescue => error
          raise "#{error}"
        end
      end

      def add_rp_env_override(rp_env)

        resource_principal_env = {}
        file = File.readlines(rp_env)
        file.each do |env|
          a = env.split("=")
          resource_principal_env[a[0]] = a[1].chomp
        end

        log.info("resource principal env is set up with #{resource_principal_env}")
        ENV.update resource_principal_env
      end

      def get_instance_md_with_retry(retries=RETRIES)
        Retriable.retriable(tries: retries, on: StandardError, timeout: 12) do
          return get_instance_md
        end
      end

      ##
      # Calculate federation endpoints based on metadata and optional inputs
      #
      # @param [String] region the region identifier
      #
      # @return [String] the federation endpoint that will be used
      def get_federation_endpoint(region)
        if region == 'r1'
          endpoint = 'https://auth.r1.oracleiaas.com/v1/x509'
        else
          if @realmDomainComponent.nil?
            log.info("Trying to get domain from local map for region #{region}")
            @realmDomainComponent = getLocalRealmDomainComponent(region)
          end
          if @realmDomainComponent.nil?
            log.warn("realm domain is null, fall back to OCI Regions")
            @realmDomainComponent = OCI::Regions.get_second_level_domain(region)
          end

          endpoint = "https://auth.#{region}.#{@realmDomainComponent}" + '/v1/x509'
        end

        log.info("endpoint is #{endpoint} in region #{region}")
        endpoint
      end

      def get_instance_md
        # v2 of IMDS requires an authorization header
        md = get_instance_md_with_url('http://169.254.169.254/opc/v2/instance/')
        if !md.nil?
          log.info "Successfully fetch instance metadata for hosts in overlay #{md}"
          return md
        else
          raise StandardError.new('Failure fetching instance metadata, possible reason is network issue or host is not OCI instance')
        end
      end

      def get_instance_md_with_url(uri_link)
        uri = URI.parse(uri_link)
        http = ::Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 2 # in seconds
        http.read_timeout = 2 # in seconds
        request = ::Net::HTTP::Get.new(uri.request_uri)
        request.add_field('Authorization', 'Bearer Oracle')
        resp = http.request(request)

        JSON.parse(resp.body)
      rescue
        log.warn("failed to get instance metadata with link #{uri_link}")
        return nil
      end

    end
  end
end
