#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_fedora_epel.sh
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
app_fedora_epel () {
  # Add access to Extra Packages for Enterprise Linux (EPEL) from the Fedora project
  case ${hostos_id} in
  amzn)
    feedback h1 'Add access to Extra Packages for Enterprise Linux (EPEL) from the Fedora project'
    manage_ale enable 'epel'
    pkgmgr install 'epel-release'
    ;;
  esac
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
