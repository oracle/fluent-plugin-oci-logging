# Copyright (c) 2024, Oracle and/or its affiliates.

require "fluent/plugin/input"
require_relative 'signer'
require 'oci'
require 'date'
require 'retriable'

module Fluent
  module Plugin

    class OracleInLoggingInput < Fluent::Plugin::Input
      include Fluent::Plugin::Signer
      Fluent::Plugin.register_input("oracle_in_logging", self)

      helpers :storage, :thread

      DEFAULT_STORAGE_TYPE = 'local'

      # Configuration Parameters
      desc 'The tag of the event'
      config_param :tag, :string, default: nil
      desc 'Compartment OCID containing log_group and log_object from where to fetch the logs'
      config_param :compartment, :string, default: nil
      desc 'Log group OCID containing log_object from where to fetch the logs'
      config_param :log_group, :string, default: nil
      desc 'Log object OCID from where to fetch the logs'
      config_param :log_object, :string, default: nil
      desc 'Start time(in RFC3339 format for e.g. 2024-09-28T00:25:00Z) from where to start fetching the logs'
      config_param :start_time, :string, default: nil
      desc 'End time(in RFC3339 format for e.g. 2024-09-28T00:25:00Z) till when to fetch the logs'
      config_param :end_time, :string, default: nil

      # Path to the PEM CA certificate file for TLS. Can contain several CA certs.
      # We are defaulting to '/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem'
      # This can be overridden for testing.
      config_param :ca_file, :string, default: nil

      config_section :storage do
        config_set_default :usage, 'oracle_in_logging_storage'
        config_set_default :@type, DEFAULT_STORAGE_TYPE
        config_set_default :path, nil
      end

      config_section :principal do
        config_param :@type, :string, default: nil
        config_param :oci_resource_principal_region, :string, default: nil
        config_param :public_resource_principal_env_file, :string, default: nil
        config_param :oci_config_path, :string, default: nil
        config_param :oci_config_profile, :string, default: nil
      end

      attr_accessor :logging_search_client

      DEFAULT_SLEEP_TIME = 10                         # Default sleep time of 10 seconds between two 10 minutes requests.
      RECORDS_PER_PAGE_LIMIT = 300
      DEFAULT_SLEEP_TIME_IN_CASE_OF_ERROR = 15*60     # 15 minutes (This is after 5 retries have been done)
      LOG_FETCH_TIME_LIMIT = 2*60                    # To not fetch logs after current timestamp - 2 minutes
      LOG_FETCH_TIME_LIMIT_SLEEP = 2*60              # sleep for 2 minutes in case end_time crosses current timestamp - LOG_FETCH_TIME_LIMIT
      DEFAULT_START_TIME = 60*60                      # Default start time of 60 minutes. Used if no start time mentioned - neither in state file , nor in fluentd config file
      LOGGING_SEARCH_TIME_WINDOW = 10*60              # Logging Search time window of 10 minutes for the logging search request. A 10 minutes window can have multiple pages (pagination).
      LOGGING_SEARCH_PAST_TIME_LIMIT = 180*24*60*60   # The latest of start_time in config file and state file should be greater than last 180 days.

      # RETRIES PARAMS (https://github.com/kamui/retriable)
      RETRIES = 5                                     # Number of attempts to make (includes initial attempt)
      BASE_INTERVAL = 3                               # The initial interval in seconds between tries
      MULTIPLIER = 3                                  # Each successive interval grows by this factor. A multiplier of 3 means the next interval will be 3x the current interval. Time - 3, 9, 27, 81, 243
      MAX_INTERVAL = 120                              # The maximum interval in seconds that any individual retry can reach.

      def initialize
        super
        @storage = nil
      end

      def initial_setup(conf)
        principal=conf.elements(name: 'principal').first
        oci_config = get_oci_config(principal)
        signer = get_signer(oci_config, principal)

        if principal["@type"] == WORKLOAD_SIGNER_TYPE
          @logging_search_client = OCI::Loggingsearch::LogSearchClient.new(config: oci_config, signer: signer, region: principal["oci_resource_principal_region"])
        else
          @logging_search_client = OCI::Loggingsearch::LogSearchClient.new(config: oci_config, signer: signer)
        end

        @search_query = "set query.use_ingest_time=\'true\';search \"#{@compartment}/#{@log_group}/#{@log_object}\""
      end

      def principal_validation_checks(principal)
        if principal.nil? || principal.empty?
          raise Fluent::ConfigError, "Missing required parameter 'principal' in source section for oracle_in_logging plugin"
        else
          if principal['@type'].nil? || principal['@type'].empty?
            raise Fluent::ConfigError, "Missing required parameter '@type' in principal section for oracle_in_logging plugin"
          else
            if principal['@type'] == WORKLOAD_SIGNER_TYPE
              if principal['oci_resource_principal_region'].nil? || principal['oci_resource_principal_region'].empty?
                raise Fluent::ConfigError, "Missing required parameter 'oci_resource_principal_region' in principal section for #{WORKLOAD_SIGNER_TYPE} signer type"
              end
            elsif principal['@type'] == RESOURCE_SIGNER_TYPE
              if principal['resource_principal_env_file'].nil? || principal['resource_principal_env_file'].empty?
                log.info "resource_principal_env_file is not set, checking if the default path exists"
                principal['resource_principal_env_file'] = RESOURCE_PRINCIPAL_ENV_FILE
              end
              if File.exist?(principal['resource_principal_env_file'])
                log.info "#{principal['resource_principal_env_file']} file exists!"
              else
                raise Fluent::ConfigError, "#{principal['resource_principal_env_file']} file does not exist on the host for #{RESOURCE_SIGNER_TYPE} signer type"
              end
            elsif principal['@type'] == USER_SIGNER_TYPE
              if principal['oci_config_path'].nil? || principal['oci_config_path'].empty?
                log.info "oci_config_path is not set, checking if the default path exists"
                principal['oci_config_path'] = OCI_CONFIG_DIR
              end
              if File.exist?(principal['oci_config_path'])
                log.info "#{principal['oci_config_path']} file exists!"
              else
                raise Fluent::ConfigError, "#{principal['oci_config_path']} file does not exist on the host for #{USER_SIGNER_TYPE} signer type"
              end
            end
          end
        end
      end
      
      def storage_validation_checks(storage_config)
        if storage_config.nil?
          raise Fluent::ConfigError, "Missing <storage> directive in the source plugin"
        end

        if storage_config['@type'].nil? || storage_config['@type'].empty?
          raise Fluent::ConfigError, "Missing required parameter '@type' in storage section for oracle_in_logging plugin"
        end

        if storage_config['@type']!=DEFAULT_STORAGE_TYPE
          raise Fluent::ConfigError, "Unsupported storage plugin type #{storage_config['@type']}. Supported type : #{DEFAULT_STORAGE_TYPE}"
        end

        if storage_config['path'].nil? || storage_config['path'].empty?
          raise Fluent::ConfigError, "Missing required parameter 'path' in storage section for oracle_in_logging plugin"
        end
      end

      def config_validation_checks(conf)
        if @tag.nil? || @tag.empty?
          raise Fluent::ConfigError, "Missing required parameter 'tag' in source section for oracle_in_logging plugin"
        end

        if @compartment.nil? || @compartment.empty?
          raise Fluent::ConfigError, "Missing required parameter 'compartment' in source section for oracle_in_logging plugin"
        end

        if @log_group.nil? || @log_group.empty?
          raise Fluent::ConfigError, "Missing required parameter 'log_group' in source section for oracle_in_logging plugin"
        end

        if @log_object.nil? || @log_object.empty?
          raise Fluent::ConfigError, "Missing required parameter 'log_object' in source section for oracle_in_logging plugin"
        end

        begin
          if @start_time
            unless @start_time!=nil && Time.iso8601(@start_time).utc.iso8601 == @start_time
              raise Fluent::ConfigError, "Invalid time format start_time format. Ensure the time is in 'YYYY-MM-DDTHH:MM:SSZ' format"
            end
          end
        rescue ArgumentError
          raise Fluent::ConfigError, "Invalid time format start_time format. Ensure the time is in 'YYYY-MM-DDTHH:MM:SSZ' format"
        end

        begin
          if @end_time
            unless @end_time!=nil && Time.iso8601(@end_time).utc.iso8601 == @end_time
              raise Fluent::ConfigError, "Invalid time format end_time format. Ensure the time is in 'YYYY-MM-DDTHH:MM:SSZ' format"
            end
          end
        rescue ArgumentError
          raise Fluent::ConfigError, "Invalid time format end_time format. Ensure the time is in 'YYYY-MM-DDTHH:MM:SSZ' format"
        end

        if @start_time!=nil && @end_time != nil && Time.parse(@start_time) >=  Time.parse(@end_time)
          raise Fluent::ConfigError, "end_time should be greater than start_time"
        end

        # Perform validation for storage section
        storage_validation_checks(conf.elements(name: 'storage').first)

        # Perform validation for principal section
        principal_validation_checks(conf.elements(name: 'principal').first)
      end

      def configure(conf)
        super

        config_validation_checks(conf)

        storage_config = conf.elements(name: 'storage').first
        @storage = storage_create(usage: 'oracle_in_logging_storage', conf: storage_config, default_type: DEFAULT_STORAGE_TYPE)

        initial_setup(conf)
      end

      def start
        super
        @storage.put(:start_time, '') unless @storage.get(:start_time)
        @storage.put(:opc_next_page, '') unless @storage.get(:opc_next_page)
        thread_create(:oracle_in_logging_runner, &method(:run))
      end

      # Computing latest time out of start_time in state file and time in the config. If none present - default start time = current time - 1 hour
      def calculate_start_time
        start_time = nil
        last_start_time = @storage.get(:start_time)
        if @start_time != nil && last_start_time == ''
          start_time = @start_time
        elsif @start_time == nil && last_start_time!=''
          start_time = last_start_time
        elsif @start_time!=nil && last_start_time!=''
          if Time.parse(last_start_time) > Time.parse(@start_time)
            start_time = last_start_time
          else
            start_time = @start_time
          end
        end

        if start_time.nil?              # No start_time in config and no start_time in state_file
          log.info "No start_time in config, neither in state file. Defaulting to 1 hour back from now."
          start_time = (Time.now - DEFAULT_START_TIME).utc.iso8601
        end

        start_time
      end

      def calculate_end_time(start_time)
        # end_time will be start_time + logging_search_time_window  -- start_time + 10 minutes
        end_time = (Time.parse(start_time) + LOGGING_SEARCH_TIME_WINDOW).utc.iso8601

        # end_time will be lesser of end_time calculated so far and the @end_time as per fluentd config if mentioned.
        if !@end_time.nil? && Time.parse(@end_time) < Time.parse(end_time)
          end_time = Time.parse(@end_time).utc.iso8601
        end

        end_time
      end

      def run
        start_time = calculate_start_time
        if Time.parse(start_time) < Time.now - LOGGING_SEARCH_PAST_TIME_LIMIT
          msg = "The latest of start_time present in config file and the state file is earlier than 180 days. Please add start_time param value within last 180 days in config file to start fetching logs."
          raise Fluent::ConfigError, msg
        end

        while thread_current_running?

          if !@end_time.nil? &&  Time.parse(start_time) >= Time.parse(@end_time)
            log.info "Log Fetching Stopped. All logs fetched till #{@end_time} as mentioned in the config. "\
                   "To continue fetching logs, remove 'end_time' from the config or increase the end_time."
            break
          end

          end_time = calculate_end_time(start_time)

          # Doing basic check for end_time to not fetch logs for timestamp within 20 minutes of current timestamp
          if Time.parse(end_time)  > Time.now - LOG_FETCH_TIME_LIMIT
            log.debug "Logs Fetched till current time - 2 minutes. sleeping for #{LOG_FETCH_TIME_LIMIT_SLEEP} seconds before retrying."
            sleep(LOG_FETCH_TIME_LIMIT_SLEEP)       # sleep for 2 minutes
            next
          end

          opc_next_page = @storage.get(:opc_next_page)     # Reading opc_next_page id from the state file (it will be either '' or some valid opc next page id)

          begin
            fetch_logs(start_time,end_time,opc_next_page)
            @storage.update(:start_time) { |v| end_time.to_s }
          rescue CustomError => e
            log.error "Error encountered during fetching logs = #{e}"
            if e.status_code == 429 || e.status_code.to_s.start_with?('5')
              log.error "Sleeping for #{DEFAULT_SLEEP_TIME_IN_CASE_OF_ERROR} seconds before retrying again"
              sleep(DEFAULT_SLEEP_TIME_IN_CASE_OF_ERROR)
              next
            else
              log.error "Exiting! Since we dont want to retry in case of errors other than Throttling and Service Errors."
              break
            end
          end

          start_time = end_time
          sleep(DEFAULT_SLEEP_TIME)
        end
      end

      def fetch_logs(start_time, end_time, opc_next_page)
        while true
          log.info "Fetching logs between [#{start_time},#{end_time}]"
          log.debug "opc_next_page = #{opc_next_page}"

          log_search_response = nil

          do_this_on_each_retry = Proc.new do |exception, tries|
            log.info "Retry Attempt: #{tries}"
          end

          begin
            Retriable.retriable :tries => RETRIES,  :base_interval => BASE_INTERVAL,   :multiplier => MULTIPLIER, :max_interval => MAX_INTERVAL, :on_retry => do_this_on_each_retry do
              if opc_next_page == ""
                log_search_response =
                  @logging_search_client.search_logs(
                    OCI::Loggingsearch::Models::SearchLogsDetails.new(
                      time_start:
                        DateTime.strptime(start_time, '%Y-%m-%dT%H:%M:%SZ'),
                      time_end:
                        DateTime.strptime(end_time, '%Y-%m-%dT%H:%M:%SZ'),
                      search_query: @search_query,
                      is_return_field_info: false
                    ),
                    limit: RECORDS_PER_PAGE_LIMIT
                  )
              else
                log_search_response =
                  @logging_search_client.search_logs(
                    OCI::Loggingsearch::Models::SearchLogsDetails.new(
                      time_start:
                        DateTime.strptime(start_time, '%Y-%m-%dT%H:%M:%SZ'),
                      time_end:
                        DateTime.strptime(end_time, '%Y-%m-%dT%H:%M:%SZ'),
                      search_query: @search_query,
                      is_return_field_info: false
                    ),
                    page: opc_next_page,
                    limit: RECORDS_PER_PAGE_LIMIT
                  )
              end
            rescue => e
              log.error "Error: #{e}"
              raise CustomError.new(e.status_code, e.message)
            end
          end

          begin
            log.debug "number of log records fetched = #{log_search_response.data.results.size()}"

            # Sending logs to further fluentd pipeline
            emit_log_records(log_search_response.data.results)

            if log_search_response.respond_to?(:next_page) && log_search_response.next_page
              opc_next_page = log_search_response.next_page
              @storage.update(:opc_next_page) { |v| opc_next_page }
              log.debug "Next page is available: #{opc_next_page}"
            else
              log.debug "No more pages available."
              opc_next_page = ""
              @storage.update(:opc_next_page) { |v| opc_next_page }
              break
            end
          rescue  => e
            log.error "Error: #{e}"
            raise CustomError.new(-1, e.message)
          end
        end
      end

      def emit_log_records(results)
        results.each do |result|
          record = result.data
          router.emit(@tag, Fluent::Engine.now, record)
        end
      end
    end

    class CustomError < StandardError
      attr_reader :status_code
      def initialize(status_code, message)
        @status_code = status_code
        super(message)
      end
    end

  end
end
