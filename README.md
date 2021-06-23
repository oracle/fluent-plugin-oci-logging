# OCI Logging Fluentd Plugin
fluent-plugin-oci-logging is the official [fluentd](https://docs.fluentd.org/)
output plugin for [OCI](https://www.oracle.com/cloud/) logging.
This project is open source, in active development and maintained by Oracle
Corp. The home page of the project is [here](https://docs.cloud.oracle.com/en-us/iaas/Content/Logging/Concepts/loggingoverview.htm).

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

    $ bundle

Or install it yourself as:

    $ gem install fluent-plugin-oci-logging

Besides the plugin, the above commands will also automatically install fluentd,
as well as the rest of the required ruby dependencies, in your system.

## Configuration
For usage with instance principals:
```
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

For usage with user principals:
```
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

In order to use user principals, you also need to have properly set up your OCI
configuration file. Instructions can be found [here](https://docs.cloud.oracle.com/en-us/iaas/Content/API/SDKDocs/cliconfigure.htm).

## Logging Setup
Detailed instructions, alongside examples, on how you can setup your logging
environment can be found in the official OCI docs [here](https://docs.cloud.oracle.com/en-us/iaas/Content/Logging/Task/managinglogs.htm).
Also, to find out how to search your logs, you can check the documentation
available [here](https://docs.cloud.oracle.com/en-us/iaas/Content/Logging/Concepts/searchinglogs.htm).

## Documentation
Full documentation, including prerequisites, installation, and configuration
instructions can be found [here](https://docs.cloud.oracle.com/en-us/iaas/Content/Logging/Concepts/loggingoverview.htm).

API reference can be found [here](https://docs.cloud.oracle.com/en-us/iaas/tools/ruby/latest/index.html).

This documentation can be found installed in your system in the gem specific directory. You can find its exact location by running the command:

    $ gem contents fluent-plugin-oci-logging

Alternatively, you can also view it via ruby's documentation tool `ri` with the following command:

    $ ri -f markdown fluent-plugin-oci-logging:README

Finally, you can view it by extracting the gem contents (the gem file itself is a tar archive).


## Known Issues

You can find information on any known issues with the SDK [here]()
and under the [Issues]() tab of this project's
[GitHub repository]().

## Questions or Feedback?
You can post an issue on the [Issues]() tab of this project's [GitHub repository]().

Addtional ways to get in touch:

* [Stack Overflow](https://stackoverflow.com/): Please use the [oracle-cloud-infrastructure](https://stackoverflow.com/questions/tagged/oracle-cloud-infrastructure) and [oci-ruby-sdk](https://stackoverflow.com/questions/tagged/oci-ruby-sdk) tags in your post
* [Developer Tools section](https://community.oracle.com/community/cloud_computing/bare-metal/content?filterID=contentstatus%5Bpublished%5D~category%5Bdeveloper-tools%5D&filterID=contentstatus%5Bpublished%5D~objecttype~objecttype%5Bthread%5D) of the Oracle Cloud forums
* [My Oracle Support](https://support.oracle.com)

## Contributing

<!-- If your project has specific contribution requirements, update the
    CONTRIBUTING.md file to ensure those requirements are clearly explained. -->

This project welcomes contributions from the community. Before submitting a pull
request, please [review our contribution guide](./CONTRIBUTING.md).

## License

Copyright (c) 2016, 2020, Oracle and/or its affiliates.  All rights reserved.

This software is dual-licensed to you under the Universal Permissive License (UPL) 1.0 as shown at https://oss.oracle.com/licenses/upl
or Apache License 2.0 as shown at http://www.apache.org/licenses/LICENSE-2.0. You may choose either license.

See [LICENSE]() for more details.
