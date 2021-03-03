#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.2.0-20210303
# File:         ec2_builder-launch.sh
# License:      GNU GPL v3
# Language:     bash
# Source:       https://github.com/mike548141/ec2_builder
#
# Description:
#  This script is a bridge between an AWS EC2 Launch Template and the script that configures the instance for its role, developed on an Amazon Linux 2 AMI using a t3a.nano instance.
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
# Beautifies the feedback to the user/log file on std_out
feedback () {
  if [ "${1}" == "title" ]
  then
    echo ''
    echo '********************************************************************************'
    echo '*                                                                              *'
    echo "*   ${2}"
    echo '*                                                                              *'
    echo '********************************************************************************'
    echo ''
  elif [ "${1}" == "h1" ]
  then
    echo ''
    echo '================================================================================'
    echo "    ${2}"
    echo '================================================================================'
    echo ''
  elif [ "${1}" == "h2" ]
  then
    echo '================================================================================'
    echo "--> ${2}"
    echo '--------------------------------------------------------------------------------'
  elif [ "${1}" == "h3" ]
  then
    echo '--------------------------------------------------------------------------------'
    echo "--> ${2}"
  elif [ "${1}" == "body" ]
  then
    echo "--> ${2}"
  elif [ "${1}" == "error" ]
  then
    echo ''
    echo '********************************************************************************'
    echo " *** Error: ${2}"
    echo ''
  else
    echo ''
    echo "*** Error in the feedback function using the following parameters"
    echo "*** P0: ${0}"
    echo "*** P1: ${1}"
    echo "*** P2: ${2}"
    echo ''
  fi
}

#======================================
# Say hello
#--------------------------------------
script_ver=`grep '^# Version:[ \t]*' ${0} | sed 's|# Version:[ \t]*||'`
hostos=`grep 'PRETTY_NAME=' /etc/os-release | sed 's|^PRETTY_NAME="||; s|"$||;'`
feedback title "ec2_builder launch script"
feedback body "Script: ${0}"
feedback body "Script version: ${script_ver}"
feedback body "Host OS: ${hostos}"
feedback body "Shell: `readlink /proc/$$/exe`"
feedback body "Running as user: `whoami`"
feedback body "Started: `date`"
feedback h2 'Preparing'

#======================================
# Declare the constants
#--------------------------------------
# These are just to download the build script, the build script defines its own tenancy, environment, and build definition
feedback body 'Setting the constants for the launch stage'
tenancy='cakeIT'
resource_environment='prod'
app='ec2_builder-web_server.sh'
# Define the parameter store structure
common_parameters="/${tenancy}/${resource_environment}/common"

# The initial AWS region setting using the instances placement so that we can connect to the AWS SSM parameter store
if [ -f '/usr/bin/ec2metadata' ]
then
  aws_region=`ec2metadata --availability-zone | cut -c 1-9`
elif [ -f '/usr/bin/ec2-metadata' ]
then
  aws_region=`ec2-metadata --availability-zone | cut -c 12-20`
else
  feedback error "Can't find ec2metadata or ec2-metadata to discover the AWS region that this instance is running in, assuming us-east-1"
  aws_region='us-east-1'
fi
feedback body "Using AWS parameter store ${common_parameters} in the ${aws_region} region"

# AWS CLI
if [ ! -f '/usr/bin/aws' ] && [ -f '/usr/bin/apt' ]
then
  # Assume AWS CLI is not installed and we have the apt package manager. Amazon Linux 2 includes AWS CLI by default but Ubuntu does not
  feedback h1 'Installing the awscli package'
  apt update
  apt --assume-yes install awscli
fi

# GitHub API secret
if [ -f '/usr/bin/aws' ]
then
  github_api_token=`aws ssm get-parameter --name "${common_parameters}/github/api_secret" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption`
fi
if [ "${github_api_token}" == "" ]
then
  feedback error 'Failed to retrieve the GitHub API secret'
fi

#======================================
# Declare the variables
#--------------------------------------

#======================================
# Lets get into it
#--------------------------------------
feedback h1 'Download the build script'
cd /root
curl -H "Authorization: token ${github_api_token}" \
     -H 'Accept: application/vnd.github.v4.raw' \
     -O \
     -f \
     -L \
     "https://raw.githubusercontent.com/mike548141/ec2_builder/master/${app}"
exit_code=${?}
if [ ${exit_code} -ne 0 ]
then
  feedback error "Failed to download the build script, curl error ${exit_code}"
else
  chmod 0740 "/root/${app}"
  feedback h2 'Execute the build script'
  "/root/${app}" go
fi
