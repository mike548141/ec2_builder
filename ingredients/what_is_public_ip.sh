#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         what_is_public_ip.sh
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
# Find what Public IP addresses are assigned to the instance
what_is_public_ip () {
  if [ -f '/usr/bin/ec2metadata' ]
  then
    public_ipv4=$(ec2metadata --public-ipv4)
    ##public_ipv6=$(ec2metadata --public-ipv6 | cut -c 14-)
  elif [ -f '/usr/bin/ec2-metadata' ]
  then
    public_ipv4=$(ec2-metadata --public-ipv4 | cut -c 14-)
    ##public_ipv6=$(ec2-metadata --public-ipv6 | cut -c 14-)
  else
    feedback error "Can't find ec2metadata or ec2-metadata to find the public IP"
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
