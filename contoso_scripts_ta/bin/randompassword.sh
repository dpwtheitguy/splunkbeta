#!/bin/bash

/opt/splunkforwarder/bin/splunk edit user admin -password `head -c 500 /dev/urandom | sha256sum | base64 | head -c 16 ; echo` -auth admin:changeme

