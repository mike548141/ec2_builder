#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         configure_awscli.sh
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
configure_awscli () {
  # Root's config for AWS CLI tools held in ~/.aws, after this is set awscli uses the rights assigned to arn:aws:iam::954095588241:user/ec2.web2.cakeit.nz instead of the instance profile arn:aws:iam::954095588241:instance-profile/ec2-web.cakeit.nz and role arn:aws:iam::954095588241:role/ec2-web.cakeit.nz
  feedback h1 'Configure AWS CLI for the root user'
  aws configure set region ${aws_region}
  aws configure set output $(aws_info ssm "${common_parameters}/awscli/cli_output")
  # Using variables because awscli will stop working when I set half of the credentials. So I need to retrieve both the variables before setting either of them
  local aws_access_key_id=$(aws_info ssm_secure "${common_parameters}/awscli/access_key_id")
  local aws_secret_access_key=$(aws_info ssm_secure "${common_parameters}/awscli/access_key_secret")
  aws configure set aws_access_key_id ${aws_access_key_id}
  aws configure set aws_secret_access_key ${aws_secret_access_key}
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
