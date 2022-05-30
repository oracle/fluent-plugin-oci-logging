# encoding: UTF-8

# fluent-plugin-oci-logging version 1.0.
#
# Copyright (c) 2021, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

require 'oci'
require 'test/unit'
require 'mocha/test_unit'
require 'webmock'
include WebMock::API

WebMock.enable!

unless File.file?('/.dockerenv')
  require 'simplecov'
  SimpleCov.start do
    add_filter do |src|
      !(src.filename =~ /^#{SimpleCov.root}\/lib/)
    end
  end
end

require 'test/unit'

require "fluent/plugin/logging_setup.rb"

class PublicloggingSetupTest < Test::Unit::TestCase
  include Fluent::Plugin::PublicLoggingSetup

  def mock_env(partial_env_hash)
    old = ENV.to_hash
    ENV.update partial_env_hash
    begin
      yield
    ensure
      ENV.replace old
    end
  end

  def teardown
    # Add per test case teardown logic here, if needed.
  end

  test 'federation_endpoint_overlay_region1' do
    region = "r1"
    assert_equal 'https://auth.r1.oracleiaas.com/v1/x509', get_federation_endpoint(region)
  end

  test 'federation_endpoint_overlay_oc1' do
    region = 'us-phoenix-1'
    assert_equal 'https://auth.us-phoenix-1.oraclecloud.com/v1/x509', get_federation_endpoint(region)
  end

  test 'federation_endpoint_overlay_oc2' do
    region ='us-luke-1'
    assert_equal 'https://auth.us-luke-1.oraclegovcloud.com/v1/x509', get_federation_endpoint(region)
  end

  test 'federation_endpoint_overlay_oc3' do
    region = 'us-gov-chicago-1'
    assert_equal 'https://auth.us-gov-chicago-1.oraclegovcloud.com/v1/x509', get_federation_endpoint(region)
  end

  test 'federation_endpoint_overlay_oc4' do
    region = 'uk-gov-london-1'
    assert_equal 'https://auth.uk-gov-london-1.oraclegovcloud.uk/v1/x509', get_federation_endpoint(region)
  end

  test 'logging_endpoint_overlay_region1' do
    region = "r1"
    assert_equal 'https://ingestion.logging.r1.oci.oracleiaas.com', get_logging_endpoint(region)
  end

  test 'logging_endpoint_overlay_oc1' do
    region = 'us-phoenix-1'
    realm = 'oc1',
    realmDomainComponent = 'oraclecloud.com'
    assert_equal 'https://ingestion.logging.us-phoenix-1.oci.oraclecloud.com', get_logging_endpoint(region)
  end

  test 'logging_endpoint_overlay_oc2' do
    region ='us-luke-1'
    assert_equal 'https://ingestion.logging.us-luke-1.oci.oraclegovcloud.com', get_logging_endpoint(region)
  end

  test 'logging_endpoint_overlay_oc3' do
    region = 'us-gov-chicago-1'
    assert_equal 'https://ingestion.logging.us-gov-chicago-1.oci.oraclegovcloud.com', get_logging_endpoint(region)
  end

  test 'logging_endpoint_overlay_oc4' do
    region = 'uk-gov-london-1'
    assert_equal 'https://ingestion.logging.uk-gov-london-1.oci.oraclegovcloud.uk', get_logging_endpoint(region)
  end

  test "with logging endpoint override" do
    region = 'uk-gov-london-1'
    endpoint_override = 'https://ingestion.logging.us-phoenix-1.oci.oraclecloud.com'
    assert_equal endpoint_override, get_logging_endpoint(region, logging_endpoint_override: endpoint_override)
  end

  test 'get instance metadata v2' do
    stub_request(:get, "http://169.254.169.254/opc/v2/instance/").
        to_return(status: 200, body: %Q({
                                    "availabilityDomain" : "YxGq:PHX-AD-2",
                                    "ociAdName" : "phx-ad-1",
                                    "region" : "us-phoenix-1",
                                    "compartmentId" : "ocid1.compartment.oc1..aaaaaaaatepf67zacevuwwkzqewno5gtvz5uhmkdqf322pgwqffx6seqjevq"
                                }), headers: {})
    md = get_instance_md
    assert_equal "us-phoenix-1", md["region"]
  end

  test 'get instance metadata v1' do
    stub_request(:get, "http://169.254.169.254/opc/v1/instance/").
        to_return(status: 200, body: %Q({
                                    "availabilityDomain" : "YxGq:PHX-AD-2",
                                    "ociAdName" : "phx-ad-1",
                                    "region" : "us-phoenix-1",
                                    "compartmentId" : "ocid1.compartment.oc1..aaaaaaaatepf67zacevuwwkzqewno5gtvz5uhmkdqf322pgwqffx6seqjevq"
                                }), headers: {})
    stub_request(:get, "http://169.254.169.254/opc/v2/instance/").
        to_return(status: 404, body: nil, headers: {})

    md = get_instance_md
    assert_equal "us-phoenix-1", md["region"]
  end

  test 'get instance metadata failure' do
    stub_request(:get, "http://169.254.169.254/opc/v1/instance/").to_return(status: 404, body: nil, headers: {})
    stub_request(:get, "http://169.254.169.254/opc/v2/instance/").to_return(status: 404, body: nil, headers: {})

    exception = assert_raise(StandardError) {get_instance_md}
    assert(exception.message.include?('Failure fetching instance metadata'),
        "Unmatched send_requests. Expected 'Failure fetching instance metadata...', got '#{exception.message}'")
  end

  test 'get user principal signer' do
    oci_config = mock('oci_config')
    oci_signer = mock('oci_signer')
    @ca_file = "test/dummy.pem"
    File.expects(:file?).returns(true)

    oci_config.expects(:user).returns("ocid1.user.test");
    oci_config.expects(:fingerprint).returns("fi:ng:er:fi:ng:er:fi:ng:er:fi:ng:er:fi:ng:er");
    oci_config.expects(:key_file).returns("/test/dummy.pem");
    oci_config.expects(:tenancy).returns("ocid1.tenancy.test");
    oci_config.expects(:region).returns("us-phoenix-1");
    oci_config.expects(:pass_phrase).returns({:pass_phrase => "youShallNotPass"});
    OCI::Signer.stubs(:new)
        .with("ocid1.user.test", "fi:ng:er:fi:ng:er:fi:ng:er:fi:ng:er:fi:ng:er",
              "ocid1.tenancy.test", "/test/dummy.pem", {:pass_phrase => {:pass_phrase => "youShallNotPass"}})
        .returns(oci_signer)
    signer = get_signer(oci_config, USER_SIGNER_TYPE)
    assert_equal oci_signer, signer
  end

  test 'get instance principal signer' do
    oci_config = mock('oci_config')
    @metadata_override = {
                              "displayName" => "phx-ad-1",
                              "canonicalRegionName" => "us-phoenix-1"
                          }
    File.expects(:file?).returns(true)
    oci_signer = mock('oci_signer')
    @federation_endpoint_override = "https://auth.us-phoenix-1.oraclecloud.com/v1/x509"
    # default ca_file
    @ca_file = '/etc/oci-pki/ca-bundle.pem'
    OCI::Auth::Signers::InstancePrincipalsSecurityTokenSigner.expects(:new)
        .with(:federation_endpoint => "https://auth.us-phoenix-1.oraclecloud.com/v1/x509",
              :federation_client_cert_bundle => "/etc/oci-pki/ca-bundle.pem")
        .returns(oci_signer)
    signer = get_signer(oci_config, AUTO_SIGNER_TYPE)
    assert_equal oci_signer, signer
  end

  test 'get instance principal signer with non-default ca_file' do
    oci_config = mock('oci_config')
    @metadata_override = {
        "displayName" => "phx-ad-1",
        "canonicalRegionName" => "us-phoenix-1"
    }
    @oci_signer = mock('oci_signer')
    @federation_endpoint_override = "https://auth.us-phoenix-1.oraclecloud.com/v1/x509"
    @ca_file = "test/dummy.pem"
    OCI::Auth::Signers::InstancePrincipalsSecurityTokenSigner.expects(:new)
        .with(:federation_endpoint => "https://auth.us-phoenix-1.oraclecloud.com/v1/x509",
              :federation_client_cert_bundle => "test/dummy.pem")
        .returns(@oci_signer)
    signer = get_signer(oci_config, AUTO_SIGNER_TYPE)
    assert_equal @oci_signer, signer
  end

  test 'get unknown principal' do
    oci_config = mock('oci_config')
    @ca_file = "test/dummy.pem"
    exception = assert_raise(StandardError) {get_signer(oci_config, "service")}
    assert(exception.message.include?("Principal type service not supported, use 'instance', 'resource' or 'user' instead"),
           "Unmatched send_requests. Expected 'Principal type service not supported, use 'instance' or 'user' instead', got '#{exception.message}'")
  end

  test "get resource principal signer" do
    @metadata_override = {
        "displayName" => "phx-ad-1",
        "canonicalRegionName" => "us-phoenix-1"
    }
    oci_config = OCI::Config.new
    @ca_file = "test/dummy.pem"
    File.expects(:file?).returns(true)
    env_file = File.join(Dir.pwd, "test", "spec", "resource_principal_env")
    oci_signer = mock('oci_signer')
    OCI::Auth::Signers.expects(:resource_principals_signer).returns(oci_signer)

    mock_env("LOCAL_TEST_ENV_FILE" => env_file) do
      assert_equal(oci_signer, get_signer(oci_config, AUTO_SIGNER_TYPE))
      assert_equal("2.2", ENV[OCI::Auth::Signers::OCI_RESOURCE_PRINCIPAL_VERSION])
    end
  end

  test 'set_default_ca_file' do
    File.stubs(:file?).returns(true)
    @ca_file = 'something/unexpect'
    @region = 'r1'
    set_default_ca_file
    assert_equal @ca_file, 'something/unexpect'

    @ca_file = 'something/unexpect'
    @region = 'us-phoenix-1'
    set_default_ca_file
    assert_equal @ca_file, 'something/unexpect'

    @ca_file = '/etc/oci-pki/ca-bundle.pem'
    @region = 'us-phoenix-1'
    set_default_ca_file
    assert_equal @ca_file, '/etc/oci-pki/ca-bundle.pem'

    # Following test cases are added to check Ubuntu for unified-monitoring-agent
    # STARTS HERE
    OS.expects(:ubuntu?).returns(true)
    @ca_file = PUBLIC_DEFAULT_LINUX_CA_PATH
    @region = 'us-phoenix-1'
    set_default_ca_file
    assert_equal @ca_file, PUBLIC_DEFAULT_UBUNTU_CA_PATH

    OS.expects(:ubuntu?).returns(true)
    @ca_file = 'something/unexpect'
    @region = 'us-phoenix-1'
    set_default_ca_file
    assert_equal @ca_file, 'something/unexpect'

    # OS.expects(:ubuntu?).returns(false) && OS.expects(:windows?).returns(false)
    OS.expects(:ubuntu?).returns(false)
    OS.expects(:windows?).returns(false)
    OS.expects(:debian?).returns(false)

    @ca_file = PUBLIC_DEFAULT_LINUX_CA_PATH
    @region = 'r1'
    set_default_ca_file
    assert_equal @ca_file, R1_CA_PATH
    # ENDS HERE

    OS.expects(:windows?).returns(true)
    @ca_file = PUBLIC_DEFAULT_LINUX_CA_PATH
    @region = 'us-phoenix-1'
    set_default_ca_file
    assert_equal @ca_file, PUBLIC_DEFAULT_WINDOWS_CA_PATH

    OS.expects(:windows?).returns(true)
    @ca_file = 'something/unexpect'
    @region = 'us-phoenix-1'
    set_default_ca_file
    assert_equal @ca_file, 'something/unexpect'

    OS.expects(:windows?).returns(false)
    OS.expects(:debian?).returns(true)
    OS.expects(:ubuntu?).returns(false)
    @ca_file = PUBLIC_DEFAULT_LINUX_CA_PATH
    @region = 'us-phoenix-1'
    set_default_ca_file
    assert_equal @ca_file, PUBLIC_DEFAULT_DEBIAN_CA_PATH
  end

  test 'get_signer_type' do
    pwd = Dir.pwd
    config_file = File.join(pwd, "test", "spec", "oci_config")
    wrong_config_file = File.join(pwd, "test", "spec", "oci_config_without_ua_profile")
    oci_config, signer_type = get_signer_type(config_dir: config_file)
    assert_equal "ap-chuncheon-1", oci_config.region
    assert_equal USER_SIGNER_TYPE, signer_type

    assert_raise RuntimeError do
        get_signer_type(principal_override: USER_SIGNER_TYPE, config_dir: "/wrong-dir")
    end

    oci_config, signer_type = get_signer_type(config_dir: wrong_config_file)
    assert_equal USER_SIGNER_TYPE, signer_type
    assert_equal oci_config.user, 'ocid1.user.oc1..default'

    oci_config, signer_type = get_signer_type(config_dir: "/wrong-dir")
    assert_equal AUTO_SIGNER_TYPE, signer_type
  end

end
