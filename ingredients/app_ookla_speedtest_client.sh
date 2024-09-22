#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_ookla_speedtest_client.sh
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
app_ookla_speedtest_client () {
  # Ookla speedtest client
  feedback h2 'Ookla client repo'
  case ${packmgr} in
  apt)
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 379CE192D401AB61
		cat <<-***EOF*** > '/etc/apt/sources.list.d/speedtest.list'
			deb https://ookla.bintray.com/debian generic main
		***EOF***
    ;;
  yum)
    cd ~
    wget --tries=2 https://bintray.com/ookla/rhel/rpm -O bintray-ookla-rhel.repo
    mv ~/bintray-ookla-rhel.repo '/etc/yum.repos.d/bintray-ookla-rhel.repo'
    ;;
  esac
  pkgmgr update
  pkgmgr install 'speedtest'
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
