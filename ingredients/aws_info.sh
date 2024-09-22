#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         aws_info.sh
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
aws_info () {
  case ${1} in
    ec2_tag)
      echo $(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == '${2}'].Value" --output text --region "${aws_region}")
    ;;
    ec2_tags)
      echo $(aws ec2 describe-tags --output text --region "${aws_region}")
    ;;
    ssm)
      echo $(aws ssm get-parameter --name "${2}" --query 'Parameter.Value' --output text --region "${aws_region}")
    ;;
    ssm_secure)
      echo $(aws ssm get-parameter --name "${2}" --query 'Parameter.Value' --output text --region "${aws_region}" --with-decryption)
    ;;
    *)
      feedback error "Function aws_info does not handle ${1}"
    ;;
  esac
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
