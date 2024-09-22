#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_sudo.sh
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
app_sudo () {
  # Configure sudo on the host to allow members of the group sudo. This is default on Ubuntu
  feedback h1 'Configure sudo'
  if [ ! $(getent group sudo) ]
  then
    feedback body 'Create sudo group'
    groupadd --gid 27 'sudo'
  fi
  if [ -z "$(grep '^%sudo.*ALL=(ALL:ALL) ALL' '/etc/sudoers')" ]
  then
    feedback body 'Give the sudo group permissions'
		cat <<-***EOF*** > '/etc/sudoers.d/group-sudo'
			# Allow members of group sudo to execute any command
			%sudo   ALL=(ALL:ALL) ALL
		***EOF***
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
