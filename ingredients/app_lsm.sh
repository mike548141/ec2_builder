#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_lsm.sh
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
app_lsm () {
  # Linux security module
  ## add a reboot to enable apparmor?
  case ${hostos_id} in
  ubuntu)
    pkgmgr install 'apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra'
    ;;
  amzn)
    pkgmgr install 'policycoreutils policycoreutils-python selinux-policy selinux-policy-targeted'
    ##selinux-activate
    sestatus
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