# fluent-plugin-oracle-in-logging (Testing Gem for Verizon)

Fluentd Input plugin to fetch the logs from OCI Logging to the Fluentd ecosystem so that from there logs can be pushed to output destination (elastic search or any other destination using the output plugins)


### Requirements
| Library/Gem      | Version   |
|------------------|-----------|
| **ruby**         | \>=2.6    |
| **fluentd**      | \>=1.16.0 |
| **oci**          | \>=2.19.0 |
| **retriable**    | \>=2.0.0  |


### Installation

#### Installation via Gemfile
Add following line into your Gemfile and bundle can do the further installation along with other gems mentioned in Gemfile
```
gem 'fluent-plugin-oracle-in-logging', git: 'https://github.com/oracle/fluent-plugin-oci-logging', glob: 'oracle-in-logging/*.gemspec', branch: 'logging-input-plugin-v0.1-beta'
```


### Configuration
```
<source>
  @type oracle_in_logging
  tag oracle_in_logging
  compartment 'ocid1.compartment.oc1..'
  log_group 'ocid1.loggroup.oc1..'
  log_object 'ocid1.log.oc1..'

  start_time '2024-10-08T07:00:00Z'
  end_time '2024-10-10T12:15:00Z'

  <principal>
  
    # ----workload identity----
    # @type workload_identity
    # oci_resource_principal_region us-ashburn-1
    
    # ----instance----
    # @type instance
    
    # ----user----
    # oci_config_path /etc/oracle-in-logging/.oci/config
    # oci_config_profile ORACLE_IN_LOGGING
    
    # ----resource----
    # @type resource
    # resource_principal_env_file "/etc/resource_principal_env"
    
  </principal>
  
  <storage>
    @type local
    path '<path-to-state-file>'
  </storage>
</source>
```


- @type (required) : The name the plugin. Its value must be oracle_in_logging
- tag (required) : The tag of the event
- compartment (required) : Compartment ocid containing log_group and log_object from where to fetch the logs
- log_group (required) : Log group ocid containing log_object from where to fetch the logs
- log_object (required) : Log object ocid from where to fetch the logs
- start_time (optional) : Check [start_time section](#computing-start-time)
- end_time (optional) : Check [end_time section](#computing-end-time)
- principal (required) :
  - option 1 : workload_identity
    - @type (required) : Type of principal. Its value will be 'workload_identity'
    - oci_resource_principal_region (required)  : The region in which the identity of a workload is running on a Kubernetes cluster to grant the workload fine-grained access to other OCI resources using Kubernetes Engine (OKE).
  - option 2 : instance
    - @type (required)  : Type of principal. Its value will be 'instance'.
  - option 3 : user
    - @type (required)  : Type of principal. Its value will be 'user'.
    - oci_config_path (optional) : The configuration file path which contains details such as the user OCID, tenancy OCID, region, private key path, and fingerprint. Default value is "/etc/oracle-in-logging/.oci/config"
    - oci_config_profile (optional) : The OCI config profile name. Default value is "ORACLE_IN_LOGGING"
  - option 4 : resource
    - @type (required)  : Type of principal. its value will be 'resource'.
    - resource_principal_env_file (optional)  : Resource principal environment file path. Default value is "/etc/resource_principal_env"
- storage
  - @type (required) : Type of storage plugin. Allowed values: local
  - path (required) : The json file path to store the state file of plugin. for e.g. /etc/state_file.json. For more details on how state file, check [state_file section](#state-file)


### Computing Start Time
Start time from where to start fetching the logs. It should be in RFC3339 format for e.g. 2024-09-28T00:25:00Z.
It is an optional parameter. Following are the various combinations for start_time with state_file

#### start_time present in config file, but absent in state_file
start_time for fetching logs = start_time from config file

#### start_time absent in config file,  but present in state_file
start_time for fetching logs = start_time from state file

#### start_time present in both config file and state file
start_time for fetching logs = latest of (config file start_time, start_time from state_file)

#### start_time absent in both config file and state_file
start_time for fetching logs = current timestamp - 1 hour      (Default to fetch logs from last 1 hour)

#### Note:
Final calculated start_time cannot be earlier than 6 months. OCI Log Search does not support querying for logs older than 180 days. If that's the case plugin will throw error. 

### Computing End Time
End time till when to fetch the logs. It should be in RFC3339 format for e.g. 2024-09-28T01:25:00Z.
It is an optional parameter. Following are the various scenarios with end_time

#### end_time not present in config file
Plugin will continue fetching logs infinitely.

#### end_time present in config file
Plugin will stop fetching logs once end_time is reached. To continue fetching logs, you need to update end_time in the config or remove it from config to fetch infinitely.

### State File
state_file parameter tell path of the file where plugin will maintain its state. We just need to provide the path of the file, plugin will automatically create it and start populating it.  The content of state_file will be as follows
```
{"start_time":"2024-10-20T09:40:00Z","opc_next_page":""}
```
**start_time:** It tells that till this time, logs have been fetched. So plugin will start fetching logs from this time.

**opc_next_page:** It is some unique id, if plugin stops in middle of some request, it may or not may not have some id to indicate that plugin need to continue from that point.


### Details on Various Errors And Plugin Behaviour

#### Fluentd Config Related Errors
If there is any config file related errors (for e.g) - mandatory parameters not provided, fluentd will stop immediately.

#### Service Errors (5XX) and Throttling Errors (429)
We have retry strategy in place to handle these errors. We will retry with exponential backoff upto 5 retries. If still not successful, plugin will sleep for 15 minutes and then continue fetching again.

#### Other Errors 
We will retry with exponential backoff upto 5 retries. Then plugin will stop fetching logs.

### Going Back into the past for fetching older logs
If plugin has already fetched the logs and still you want to fetch the logs again from the past, then you need to delete the state_file and then set the past start_time accordingly in the fluentd config file. And then start fluentd.

### Emitting Metrics
This Plugin does not emit any metrics. If metrics are needed, ideal way is to collect using prometheus plugin.

## Copyright

* Copyright(c) 2024- Oracle
* License
  * Apache License, Version 2.0
