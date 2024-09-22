#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_rkhunter.sh
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
app_rkhunter () {
  # rkhunter
  case ${packmgr} in
  apt)
    # Automate the postfix package install by selecting No configuration. Postfix is pulled in as a dependency of rkhunter
    echo 'postfix	postfix/main_mailer_type	select	No configuration' | debconf-set-selections
    ;;
  esac
  pkgmgr install 'rkhunter'
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
