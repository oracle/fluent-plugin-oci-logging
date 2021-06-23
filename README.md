# Oracle Cloud Infrastructure Fluentd Plugin

This is the official [fluentd](https://docs.fluentd.org/) plugin for the Oracle
Cloud Infrastructure (OCI) Logging service. This project is open source, in
active development and maintained by Oracle.

## Requirements
To use this fluentd plugin, you must have:

* An Oracle Cloud Infrastructure acount.
* A user created in that account, in a group with a policy that grants the
desired permissions. This can be a user for yourself, or another person/system
that needs to call the API. For an example of how to set up a new user, group,
compartment, and policy, see [Adding Users](https://docs.cloud.oracle.com/Content/GSG/Tasks/addingusers.htm)
in the Getting Started Guide. For a list of typical policies you may want to
use, see [Common Policies](https://docs.cloud.oracle.com/Content/Identity/Concepts/commonpolicies.htm)
in the User Guide.
* Ruby version 2.2 or later running on Mac, Linux or Windows.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'fluent-plugin-oci-logging'
```

And then execute:

```shell
$ bundle
```

Or install it yourself as:

```
gem install fluent-plugin-oci-logging
```

Besides the plugin, the above commands will also automatically install fluentd,
as well as the rest of the required ruby dependencies, in your system.

## Configuration

For usage with [instance principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm):

```xml
<source>
  @type dummy
  tag test
  dummy {"test":"message"}
</source>
<match **>
    @type oci_logging
    log_object_id  ocid1.log.oc1.XXX.xxx
</match>
```

For usage with an [API signing key]( https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm):

```xml
<source>
  @type dummy
  tag test
  dummy {"test":"message"}
</source>
<match **>
    @type oci_logging
    principal_override user
    log_object_id  ocid1.log.oc1.XXX.xxx
</match>
```

To authenticate as a particular user, you need to [generate an API Signing Key](https://docs.cloud.oracle.com/en-us/iaas/Content/API/SDKDocs/cliconfigure.htm) for that user.

## Logging Setup

Detailed instructions, alongside examples, on how you can setup your logging
environment can be found in the official [OCI docs](https://docs.cloud.oracle.com/en-us/iaas/Content/Logging/Task/managinglogs.htm).
Also, to find out how to search your logs, you can check the documentation
for [log search](https://docs.cloud.oracle.com/en-us/iaas/Content/Logging/Concepts/searchinglogs.htm).

## Documentation

Full documentation, including prerequisites, installation, and configuration
instructions can be found [here](https://docs.cloud.oracle.com/en-us/iaas/Content/Logging/Concepts/loggingoverview.htm).

API reference can be found [here](https://docs.cloud.oracle.com/en-us/iaas/tools/ruby/latest/index.html).

This documentation can be found installed in your system in the gem specific directory. You can find its exact location by running the command:

```shell
gem contents fluent-plugin-oci-logging
```

Alternatively, you can also view it via ruby's documentation tool `ri` with the following command:

```shell
ri -f markdown fluent-plugin-oci-logging:README
```

Finally, you can view it by extracting the gem contents (the gem file itself is a tar archive).


## Known Issues

You can find information on any known issues with the SDK under the [Issues](https://github.com/oracle/fluent-plugin-oci-logging/issues) tab.

## Questions or Feedback?

Please [open an issue for any problems or questions](https://github.com/oracle/fluent-plugin-oci-logging/issues) you may have.

Addtional ways to get in touch:

* [Stack Overflow](https://stackoverflow.com/): Please use the [oracle-cloud-infrastructure](https://stackoverflow.com/questions/tagged/oracle-cloud-infrastructure) and [oci-ruby-sdk](https://stackoverflow.com/questions/tagged/oci-ruby-sdk) tags in your post
* [Developer Tools section](https://community.oracle.com/community/cloud_computing/bare-metal/content?filterID=contentstatus%5Bpublished%5D~category%5Bdeveloper-tools%5D&filterID=contentstatus%5Bpublished%5D~objecttype~objecttype%5Bthread%5D) of the Oracle Cloud forums
* [My Oracle Support](https://support.oracle.com)

## Contributing

This project welcomes contributions from the community. Before submitting a pull
request, please [review our contribution guide](./CONTRIBUTING.md).

## Security

Please consult the [security guide](./SECURITY.md) for our responsible security
vulnerability disclosure process.

## License

Copyright (c) 2021, Oracle and/or its affiliates.

This software is dual-licensed to you under the Universal Permissive License (UPL) 1.0 as shown at <https://oss.oracle.com/licenses/upl>
or Apache License 2.0 as shown at <http://www.apache.org/licenses/LICENSE-2.0>. You may choose either license.

See [LICENSE](./LICENSE.txt) for more details.
