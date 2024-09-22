#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         what_is_instance_meta.sh
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
what_is_instance_meta () {
  # AWS region and EC2 instance ID so we can use awscli
  if [ -f '/usr/bin/ec2metadata' ]
  then
    aws_region=$(ec2metadata --availability-zone | cut -c 1-9)
    instance_id=$(ec2metadata --instance-id)
  elif [ -f '/usr/bin/ec2-metadata' ]
  then
    aws_region=$(ec2-metadata --availability-zone | cut -c 12-20)
    instance_id=$(ec2-metadata --instance-id | cut -c 14-)
  else
    feedback error "Can't find ec2metadata or ec2-metadata"
  fi
  if [ -z "${aws_region}" ]
  then
    aws_region="${aws_region_default}"
    feedback error "AWS region not set, assuming ${aws_region}"
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
