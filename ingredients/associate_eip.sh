#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         associate_eip.sh
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
associate_eip () {
  # Get the AWS Elastic IP address used to web host
  eip_allocation_id=$(aws_info ssm "${app_parameters}/eip_allocation_id")
  # If the variable is blank then don't assign an EIP, assume there is a load balancer instead
  if [ -z "${eip_allocation_id}" ]
  then
    feedback h1 'EIP variable is blank, I assume the IP address for web2.cakeit.nz is bound to a load balancer'
  else
    # Allocate the AWS EIP to this instance
    feedback h1 'Allocate the EIP public IP address to this instance'
    ## Find out what instance is currently holding the EIP if any
    # Allocate the EIP
    aws ec2 associate-address --instance-id ${instance_id} --allocation-id ${eip_allocation_id} --region ${aws_region}
    # Update the public IP address assigned now the EIP is associated
    feedback body 'Sleep for 5 seconds to allow metadata to update after the EIP association'
    sleep 5
    what_is_public_ip
    feedback body "EIP address ${public_ipv4} associated"
  fi
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
