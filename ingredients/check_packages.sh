#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         check_packages.sh
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
check_packages () {
  # Handle a list of multiple packages by looping through them
  for package in ${2}
  do
    # Lookup the package name if given a file name
    if [ $(echo ${package} | grep -i '\.deb$') ]
    then
      local pkg_name=$(dpkg --info ${package} | grep ' Package: ' | sed 's|^ Package: ||;')
    elif [ $(echo ${package} | grep -i '\.rpm$') ]
    then
      ## I should add support for RPM packages
      local pkg_name='oops TBC'
    else
      local pkg_name=${package}
    fi
    
    # Check if the package is listed in the package manger database
    local pkg_status=$(dpkg-query --showformat='${Status}' --show ${pkg_name})
    if [ "${1}" == "present" ] && [ ${pkg_status} != 'install ok installed' ]
    then
      # Not installed i.e. not listed in the package manger database
      feedback error "The package ${pkg_name} has not installed properly (${pkg_status})"
    elif [ "${1}" == "absent" ] && [ ${pkg_status} == 'install ok installed' ]
    then
      feedback error "The package ${pkg_name} is already installed (${pkg_status})"
    fi
  done
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
