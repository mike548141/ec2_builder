#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_tripwire.sh
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
app_tripwire () {
  # tripwire
  case ${packmgr} in
  apt)
    # Automate the tripwire package install
    echo 'tripwire	tripwire/use-sitekey	boolean	false' | debconf-set-selections
    echo 'tripwire	tripwire/use-localkey	boolean	false' | debconf-set-selections
    echo 'tripwire	tripwire/installed	note	' | debconf-set-selections
    ;;
  esac
  pkgmgr install 'tripwire'
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
