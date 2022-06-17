# encoding: UTF-8

# fluent-plugin-oci-logging version 1.0.
#
# Copyright (c) 2021, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

require_relative '../helper'
require 'test/unit'
require 'mocha/test_unit'

require 'fluent/plugin/logging_utils.rb'

class PublicloggingUtilsTest < Test::Unit::TestCase
  include Fluent::Plugin::PublicLoggingUtils

  setup do
    @client = mock('client')
  end

  test 'flatten_hash' do
    original_hash = {
      'a' => 'b',
      'c' => ['d', 'e', 'f'],
      'g' => {
        'h': 'i',
        'k': ['l', 'm', 'n']
      },
      'o' => {
        'p' => {
          'q' => 'r'
        }
      },
      'log' => 'foo'
    }

    final_hash = {
      'a' => 'b',
      'c' => ['d', 'e', 'f'],
      'g.h' => 'i',
      'g.k' => ['l', 'm', 'n'],
      'o.p.q' => 'r',
      'msg' => 'foo'
    }

    test_hash = flatten_hash(original_hash)
    assert(
      test_hash == final_hash,
      "Flattened hashes mismatch. Got: #{test_hash}. Expected: #{final_hash}"
    )
  end

  test 'build_request' do
    @hosname = "dummy_hostclass"
    time = Time.new
    log_batches_map = {}
    build_request(time, {}, 'test_tag', log_batches_map, '/path/to/file')
    assert(
        log_batches_map['test_tag/path/to/file'].defaultlogentrytime == Time.at(time).utc.strftime('%FT%T.%LZ'),
        "Expected time #{time}, got #{log_batches_map['test_tag/path/to/file'].defaultlogentrytime}")
    # log_batches_map = {}
    build_request(time, {'key' => 'value'}, 'test_tag', log_batches_map, '/path/to/file')
    assert(
        log_batches_map['test_tag/path/to/file'].entries[1].data == "{\"key\":\"value\"}",
        "Expected time #{'{\'key\' : \'value\'}'}, got #{log_batches_map['test_tag/path/to/file'].entries[1].data}")
  end

  test 'build_request with encoding' do
    @hosname = "dummy_hostclass"
    time = Time.new
    log_batches_map = {}
    build_request(time, {}, 'test_tag', log_batches_map, '/path/to/file')
    assert(
        log_batches_map['test_tag/path/to/file'].defaultlogentrytime == Time.at(time).utc.strftime('%FT%T.%LZ'),
        "Expected time #{time}, got #{log_batches_map['test_tag/path/to/file'].defaultlogentrytime}")
    # log_batches_map = {}
    build_request(time, {'key' => "value \x92 ".force_encoding("ASCII-8BIT")}, 'test_tag', log_batches_map, '/path/to/file')
    expected_value = {'key' => "value \x92 ".force_encoding("ASCII-8BIT").to_s.force_encoding("ISO-8859-1").encode("UTF-8")}.to_json
    assert(
        log_batches_map['test_tag/path/to/file'].entries[1].data == expected_value,
        "Expected time #{expected_value}, got #{log_batches_map['test_tag/path/to/file'].entries[1].data}")
  end

  test 'send_request' do
    SecureRandom.expects(:uuid).returns('dummy-uuid')
    time = Time.now
    Time.stubs(:now).returns(time)
    Time.stubs(:at).returns(time)
    @log_object_id = 'logocid-test'
    @hostname = "dummy_host"
    entry = OCI::Loggingingestion::Models::LogEntry.new(
        {data: '{"key" => "value"}',
         time: '2018-09-12T22:47:12.613Z', id: 'dummy-uuid'})
    OCI::Loggingingestion::Models::LogEntry.stubs(:new).returns(entry)
    log_entry_batch = OCI::Loggingingestion::Models::LogEntryBatch.new(
        {source: "dummy_host", type: "com.oraclecloud.logging.custom.test_tag", subject: "/path/to/file",
         defaultlogentrytime: time.utc.strftime('%FT%T.%LZ'), entries: [entry]}
    )

    expected_log_request = OCI::Loggingingestion::Models::PutLogsDetails.new(
        {specversion: PUBLIC_CLIENT_SPEC_VERSION,
         log_entry_batches: [
             log_entry_batch
         ] }
    )
    response = Response.new(200, "request-id")
    @client
        .expects(:put_logs)
        .with('logocid-test', expected_log_request)
        .returns(response)
    log_batches_map = {}
    build_request(Time.new, {'key' => 'value'}, 'test_tag', log_batches_map, '/path/to/file')
    assert(send_requests(log_batches_map), "send_requests failed")
  end


  test 'test tag to log_type conversion' do
    assert_equal('client', get_modified_tag('client'))
    assert_equal('client', get_modified_tag('7789.client'))
    assert_equal('client.more', get_modified_tag('7789.client.more'))
    assert_equal('client.more.nowmore', get_modified_tag('7789.client.more.nowmore'))
    assert_equal('client.more.nowmore.superdoopermore', get_modified_tag('7789.client.more.nowmore.superdoopermore'))
    assert_equal('empty', get_modified_tag(nil))
  end

  class Response
    attr_reader :status
    attr_reader :request_id

    def initialize(status, request_id)
      @status = status
      @request_id = request_id
    end
  end
end
