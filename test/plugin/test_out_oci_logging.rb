# fluent-plugin-oci-logging version 1.0.
#
# Copyright (c) 2021, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

# frozen_string_literal: true
require_relative '../helper'
require 'fluent/test/helpers' # for event_time()
require 'json'
require 'pp'
require "test/unit"
require 'mocha/test_unit'
require 'oci'

require_relative './testutil'

# The function has to be called before requiring plugin file
stub_instance_md_req_for_plugin "oci_logging"

require 'fluent/plugin/out_oci_logging.rb'

class OutOCIPublicloggingOutputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
    # common stubs
    @oci_config = mock('oci_config')
    @oci_signer = mock('oci_signer')
    @client = mock('client')
    @api_client = mock('api_client')
    @signer_type = mock('signer_type')
    Fluent::Plugin::OCILoggingOutput.any_instance.stubs(:create_oci_config).returns(@oci_config)
  end

  def set_instance_principal_expectations
    @client.expects(:api_client).returns(@api_client)
    @api_client.expects(:request_option_overrides=).with(ca_file: "test/dummy.pem")
    OCI::Config.expects(:new).returns(@oci_config)
    OCI::Auth::Signers::InstancePrincipalsSecurityTokenSigner.expects(:new)
        .with(:federation_endpoint => "https://auth.us-phoenix-1.oraclecloud.com/v1/x509",
              :federation_client_cert_bundle => "test/dummy.pem")
        .returns(@oci_signer)
    OCI::Loggingingestion::LoggingClient.expects(:new)
        .with(:config => @oci_config, :endpoint =>'https://ingestion.logging.us-phoenix-1.oci.oraclecloud.com',
              :signer =>@oci_signer, :proxy_settings => nil, :retry_config => nil)
        .returns(@client)
  end

  def set_user_api_key_expectations
    @client.expects(:api_client).returns(@api_client)
    @api_client.expects(:request_option_overrides=).with(ca_file: "test/dummy.pem")
    # setting oci_config expectations
    @oci_config.expects(:user).returns("ocid1.user.test");
    @oci_config.expects(:fingerprint).returns("fi:ng:er:fi:ng:er:fi:ng:er:fi:ng:er:fi:ng:er");
    @oci_config.expects(:key_file).returns("/test/dummy.pem");
    @oci_config.expects(:tenancy).returns("ocid1.tenancy.test");
    @oci_config.expects(:region).returns("us-phoenix-1");
    @oci_config.expects(:pass_phrase).returns({:pass_phrase => "youShallNotPass"});
    OCI::ConfigFileLoader.expects(:load_config).returns(@oci_config)

    # setting signer expectations
    OCI::Signer.expects(:new)
        .with("ocid1.user.test", "fi:ng:er:fi:ng:er:fi:ng:er:fi:ng:er:fi:ng:er",
              "ocid1.tenancy.test", "/test/dummy.pem", {:pass_phrase => {:pass_phrase => "youShallNotPass"}})
        .returns(@oci_signer)
    ::OCI::Loggingingestion::LoggingClient.expects(:new)
        .with(:config => @oci_config, :endpoint =>'https://ingestion.logging.us-phoenix-1.oci.oraclecloud.com',
              :signer =>@oci_signer, :proxy_settings => nil, :retry_config => nil)
        .returns(@client)
  end

  # Other unit tests are setting env variable[logging endpoint]
  # which is throwing off the tests here and need to clear it out
  def mock_env(partial_env_hash)
    old = ENV.to_hash
    ENV.update partial_env_hash
    begin
      yield
    ensure
      ENV.replace old
    end
  end

  def create_driver(conf)
    d = Fluent::Test::Driver::Output.new(Fluent::Plugin::OCILoggingOutput)
    d.configure(conf)
  end

  def get_test_record(msg)
    {
        "msg" => msg,
        "severity" => "info"
    }
  end

  def conf(override = '', buff_opts='')
    %{
      log_object_id  logocid-test
      ca_file test/dummy.pem
      #{override}
      metadata_override {
        "availabilityDomain": "ad1",
        "canonicalRegionName" : "us-phoenix-1",
        "displayName": "testdisplayname"
      }
      #{buff_opts}
    }
  end

 # ----------------------------------------
  test 'instance principals auth' do
    set_instance_principal_expectations
    mock_env('LOGGING_FRONTEND' => nil) do
      # ----------------------------------------
      d = create_driver(conf('principal_override auto',''))
      ts = "2019-11-05T19:55:14.073+00:00"
      record = get_test_record("Starting overlay audit")
      # stub the UUID and timestamps
      SecureRandom.expects(:uuid).returns("dummy-uuid")
      time = Time.now
      Time.stubs(:now).returns(time)
      Time.stubs(:at).returns(time)

      entry = OCI::Loggingingestion::Models::LogEntry.new(
              {data: '{"msg"=>"Starting overlay audit", "severity"=>"info"}',
               time: time.utc.strftime('%FT%T.%LZ'), id: 'dummy-uuid'})
      OCI::Loggingingestion::Models::LogEntry.stubs(:new).returns(entry)
      log_entry_batch = OCI::Loggingingestion::Models::LogEntryBatch.new(
          {source: "testdisplayname", type: "com.oraclecloud.logging.custom.empty", subject: "",
           defaultlogentrytime: time.utc.strftime('%FT%T.%LZ'), entries: [entry]}
      )

      expected_log_request = OCI::Loggingingestion::Models::PutLogsDetails.new(
          {specversion: '1.0',
                   log_entry_batches: [
                       log_entry_batch
                   ] }
      )

      @client
          .expects(:put_logs)
          .with('logocid-test', expected_log_request)
          .returns({status: 200, request_id: 123})

      # run the test driver
      d.run do
        d.feed("tag", event_time(ts), record)
      end
      d.events.clear
    end
  end

  # ----------------------------------------
  test 'user api key auth' do
    set_user_api_key_expectations
    mock_env('LOGGING_FRONTEND' => nil) do
      # ----------------------------------------
      d = create_driver(conf('principal_override user',''))
      ts = "2019-11-05T19:55:14.073+00:00"
      record = get_test_record("Starting overlay audit")
      # stub the UUID and timestamps
      SecureRandom.expects(:uuid).returns("dummy-uuid")
      time = Time.now
      Time.stubs(:now).returns(time)
      Time.stubs(:at).returns(time)

      entry = OCI::Loggingingestion::Models::LogEntry.new(
          {data: '{"msg"=>"Starting overlay audit", "severity"=>"info"}',
           time: time.utc.strftime('%FT%T.%LZ'), id: 'dummy-uuid'})
      OCI::Loggingingestion::Models::LogEntry.stubs(:new).returns(entry)
      log_entry_batch = OCI::Loggingingestion::Models::LogEntryBatch.new(
          {source: Socket.gethostname, type: "com.oraclecloud.logging.custom.empty", subject: "",
           defaultlogentrytime: time.utc.strftime('%FT%T.%LZ'), entries: [entry]}
      )

      expected_log_request = OCI::Loggingingestion::Models::PutLogsDetails.new(
          {specversion: '1.0',
           log_entry_batches: [
               log_entry_batch
           ] }
      )

      @client
          .expects(:put_logs)
          .with('logocid-test', expected_log_request)
          .returns({status: 200, request_id: 123})
      # run the test driver
      d.run do
        d.feed("tag", event_time(ts), record)
      end
      d.events.clear
    end
  end
end
