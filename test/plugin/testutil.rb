# fluent-plugin-oci-logging version 1.0.
#
# Copyright (c) 2021, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

require 'webmock'
include WebMock::API

WebMock.enable!

# This line is to stub request in class method in OCI::Environment.
# It will keep retrying and make unit test slow without stubbing request
def stub_instance_md_req_for_plugin(name)
  puts "Stub instance metadata request in class method in OCI::Environment, which is used in #{name}"
  instance_metadata_url = "http://169.254.169.254/opc/v1/instance/"
  stub_request(:get, instance_metadata_url).
      to_return(status: 200, body: %Q({
                                    "availabilityDomain" : "YxGq:PHX-AD-2",
                                    "ociAdName" : "phx-ad-1",
                                    "region" : "us-phoenix-1",
                                    "compartmentId" : "ocid1.compartment.oc1..aaaaaaaatepf67zacevuwwkzqewno5gtvz5uhmkdqf322pgwqffx6seqjevq"
                                }), headers: {})
  instance_metadata_url = "http://169.254.169.254/opc/v2/instance/"
  stub_request(:get, instance_metadata_url).
      to_return(status: 200, body: %Q({
                                    "availabilityDomain" : "YxGq:PHX-AD-2",
                                    "ociAdName" : "phx-ad-1",
                                    "region" : "us-phoenix-1",
                                    "compartmentId" : "ocid1.compartment.oc1..aaaaaaaatepf67zacevuwwkzqewno5gtvz5uhmkdqf322pgwqffx6seqjevq"
                                }), headers: {})
end
