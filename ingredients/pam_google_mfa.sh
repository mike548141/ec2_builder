#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         pam_google_mfa.sh
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
pam_google_mfa () {
  # Google Authenticator adds MFA capability to PAM - https://aws.amazon.com/blogs/startups/securing-ssh-to-amazon-ec2-linux-hosts/ and https://ubuntu.com/tutorials/configure-ssh-2fa#2-installing-and-configuring-required-packages
  feedback h1 'Google Authenticator to support MFA'
  case ${packmgr} in
  apt)
    pkgmgr install 'libpam-google-authenticator'
    ;;
  yum)
    pkgmgr install 'google-authenticator'
    ;;
  esac
  ## Add the configuration to use this with SSH
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
