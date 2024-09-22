#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         mount_efs_volume.sh
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
mount_efs_volume () {
  # Install AWS EFS helper and mount the EFS volume for vhost data
  feedback h1 'AWS EFS helper'
  case ${packmgr} in
  apt)
    git clone https://github.com/aws/efs-utils '/opt/aws/efs-utils/'
    cd '/opt/aws/efs-utils'
    ./build-deb.sh
    pkgmgr install ./build/amazon-efs-utils-*.deb
    ;;
  yum)
    pkgmgr install 'amazon-efs-utils'
    ;;
  esac
  feedback h3 'Mount the EFS volume for vhost data'
  # The AWS EFS volume and mount point used to hold virtual host config, content and logs that is shared between web hosts (aka instances)
  efs_mount_point=$(aws_info ssm "${app_parameters}/awsefs/mount_point")
  efs_volume=$(aws_info ssm "${app_parameters}/awsefs/volume")
  mkdir --parents ${efs_mount_point}
  if mountpoint -q ${efs_mount_point}
  then
    umount ${efs_mount_point}
  fi
  mount -t efs -o tls ${efs_volume}:/ ${efs_mount_point}
  feedback body 'Set it to auto mount at boot'
	cat <<-***EOF*** >> '/etc/fstab'
		# Mount AWS EFS volume ${efs_volume} for the web root data
		${efs_volume}:/ ${efs_mount_point} efs tls,_netdev 0 0
	***EOF***
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
