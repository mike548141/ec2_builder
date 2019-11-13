#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.0.1-20191113
# File:         ec2_builder-launch.sh
# License:      GNU GPL v3
# Language:     bash
#
# Description:
#  This script is a bridge between an AWS EC2 Launch Template and the script that configures the instance for its role, developed on an Amazon Linux 2 AMI.
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
# Define the arrays
#--------------------------------------

#======================================
# Define the functions
#--------------------------------------

#======================================
# Declare the constants
#--------------------------------------
echo 'Setting the initial constants'
# Define the keys constants to decide what we are building
tenancy='cakeIT'
resource_environment='prod'
service_group='web.cakeit.nz'
app='ec2_builder-web_server.sh'

# Define the parameter store structure
common_parameters="/${tenancy}/${resource_environment}/common"
# The initial AWS region setting using the instances placement so that we can connect to the AWS SSM parameter store
aws_region=`ec2-metadata --availability-zone | cut -c 12-20`

# GitHub API secret
github_api_token=`aws ssm get-parameter --name "${common_parameters}/github/api_token" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption`

#======================================
# Declare the variables
#--------------------------------------

#======================================
# Lets get into it
#--------------------------------------
echo 'Download the build script'
cd /root
curl -H "Authorization: token 326dce3b77e0c9161d729753cb65661bbaccd0ba" \
-H 'Accept: application/vnd.github.v4.raw' \
-O -L "https://raw.githubusercontent.com/mike548141/ec2_builder/master/ec2_builder-web_server.sh"

chmod 0700 /root/ec2_builder-web_server.sh
echo 'Execute the build script'
/root/ec2_builder-web_server.sh
