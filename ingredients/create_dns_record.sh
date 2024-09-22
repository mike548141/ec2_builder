#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         create_dns_record.sh
# License:      GNU GPL v3
# Language:     bash
# Source:       https://github.com/mike548141/ec2_builder
#
# Description:
#
# References:
#
# Pre-requisite:
#
# Updates:
#
# Improvements to be made:
#

#======================================
# Declare the arrays
#--------------------------------------

#======================================
# Declare the libraries and functions
#--------------------------------------
create_dns_record () {
  # Create a DNS entry for the web host
  feedback h1 'Create a DNS entry on Cloudflare for this instance'
  # Cloudflare API secret
  cloudflare_zoneid=$(aws_info ssm_secure "${common_parameters}/cloudflare/${hosting_domain}/zone_id")
  local cloudflare_api_token=$(aws_info ssm_secure "${common_parameters}/cloudflare/${hosting_domain}/api_token")
  curl -X POST "https://api.cloudflare.com/client/v4/zones/${cloudflare_zoneid}/dns_records" \
       -H "Authorization: Bearer ${cloudflare_api_token}" \
       -H "Content-Type: application/json" \
       --data '{"type":"A","name":"'"${instance_id}"'","content":"'"${public_ipv4}"'","ttl":1,"priority":10,"proxied":false}'
  ##curl -X POST "https://api.cloudflare.com/client/v4/zones/${cloudflare_zoneid}/dns_records" \
  ##     -H "Authorization: Bearer ${cloudflare_api_token}" \
  ##     -H "Content-Type: application/json" \
  ##     --data '{"type":"AAAA","name":"'"${instance_id}"'","content":"'"${public_ipv6}"'","ttl":1,"priority":10,"proxied":false}'
  feedback h3 'Sleeping for 5 seconds to allow that DNS change to replicate'
  sleep 5
}

#======================================
# Say hello
#--------------------------------------

#======================================
# Declare the constants
#--------------------------------------

#======================================
# Declare the variables
#--------------------------------------

#======================================
# Lets get into it
#--------------------------------------
