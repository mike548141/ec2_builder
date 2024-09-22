#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_osquery.sh
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
app_osquery () {
  # OS Query
  feedback h3 'Add the osquery repo and trust the GPG key'
  case ${packmgr} in
  apt)
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 1484120AC4E9F8A1A577AEEE97A80C63C9D8B80B
    add-apt-repository 'deb [arch=amd64] https://pkg.osquery.io/deb deb main'
    ;;
  yum)
    curl -L https://pkg.osquery.io/rpm/GPG | tee '/etc/pki/rpm-gpg/RPM-GPG-KEY-osquery'
    rpm --import '/etc/pki/rpm-gpg/RPM-GPG-KEY-osquery'
    yum-config-manager --add-repo https://pkg.osquery.io/rpm/osquery-s3-rpm.repo
    yum-config-manager --enable osquery-s3-rpm
    ;;
  esac
  pkgmgr update
  pkgmgr install 'osquery'
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
