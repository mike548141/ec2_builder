#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         mount_s3_bucket.sh
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
mount_s3_bucket () {
  # Install Fuse S3FS and mount the S3 bucket for web server data - https://github.com/s3fs-fuse/s3fs-fuse
  feedback h1 'Fuse S3FS'
  ## The S3 function should run configure_awscli since its dependent upon it
  case ${hostos_id} in
  ubuntu)
    pkgmgr install 's3fs'
    ;;
  amzn)
    pkgmgr install 's3fs-fuse'
    ;;
  esac
  feedback h3 'Configure FUSE'
  sed -i.bak 's|^# user_allow_other$|user_allow_other|' '/etc/fuse.conf'
  feedback h3 'Mount the S3 bucket for static web data'
  mkdir --parents ${s3_mount_point}
  if mountpoint -q ${s3_mount_point}
  then
    umount ${s3_mount_point}
  fi
  s3fs ${s3_bucket} ${s3_mount_point} -o allow_other -o use_path_request_style
  feedback body 'Set it to auto mount at boot'
	cat <<-***EOF*** >> '/etc/fstab'
		# Mount AWS S3 bucket ${s3_bucket} for static web data
		s3fs#${s3_bucket} ${s3_mount_point} fuse _netdev,allow_other,use_path_request_style 0 0
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
