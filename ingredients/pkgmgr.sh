#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         pkgmgr.sh
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
# Install an application package
pkgmgr () {
  # Check that the package manager is not already running
  check_pid_lock ${packmgr}
  case ${1} in
    update)
      feedback h3 'Get updates from package repositories'
      case ${packmgr} in
        apt)
          apt-get --assume-yes update
          local exit_code=${?}
        ;;
        yum)
          yum --assumeyes update
          local exit_code=${?}
        ;;
      esac
    ;;
    upgrade)
      feedback h3 'Upgrade installed packages'
      case ${packmgr} in
        apt)
          apt-get --assume-yes upgrade
          local exit_code=${?}
        ;;
        yum)
          yum --assumeyes upgrade
          local exit_code=${?}
        ;;
      esac
    ;;
    install)
      # Check if any of the packages are already installed
      check_packages absent "${2}"
      feedback h3 "Install ${2}"
      case ${packmgr} in
        apt)
          apt-get --assume-yes install ${2}
          local exit_code=${?}
        ;;
        yum)
          yum --assumeyes install ${2}
          local exit_code=${?}
        ;;
      esac
      # Check that each of the packages are now showing as installed in the package database to verify it completed properly
      check_packages present "${2}"
    ;;
    *)
      feedback error "The package manager function can not understand the command ${1}"
    ;;
  esac
  if [ ${exit_code} -ne 0 ]
  then
    feedback error "${packmgr} exit code ${exit_code}"
  else
    feedback body "Thumbs up, ${packmgr} exit code ${exit_code}"
  fi
  # Wait for the package manager to terminate
  check_pid_lock ${packmgr}
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
