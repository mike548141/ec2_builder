#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.2.14-20210306
# File:         ec2_builder-launch.sh
# License:      GNU GPL v3
# Language:     bash
# Source:       https://github.com/mike548141/ec2_builder
#
# Description:
#  This script is a bridge between an AWS EC2 Launch Template and the script that configures the instance for its role, developed on an Amazon Linux 2 AMI and extended to support ubuntu 20.04 LTS AMI; using a t3a.nano instance.
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
# Beautifies the feedback to the user/log file on std_out
feedback () {
  case ${1} in
  title)
    echo ''
    echo '********************************************************************************'
    echo '*                                                                              *'
    echo "*   ${2}"
    echo '*                                                                              *'
    echo '********************************************************************************'
    echo ''
    ;;
  h1)
    echo ''
    echo '================================================================================'
    echo "    ${2}"
    echo '================================================================================'
    echo ''
    ;;
  h2)
    echo ''
    echo '================================================================================'
    echo "--> ${2}"
    echo '--------------------------------------------------------------------------------'
    echo ''
    ;;
  h3)
    echo '--------------------------------------------------------------------------------'
    echo "--> ${2}"
    ;;
  body)
    echo "--> ${2}"
    ;;
  error)
    echo ''
    echo '********************************************************************************'
    echo " *** Error: ${2}"
    echo ''
    ;;
  *)
    echo ''
    echo "*** Error in the feedback function using the following parameters"
    echo "*** P0: ${0}"
    echo "*** P1: ${1}"
    echo "*** P2: ${2}"
    echo ''
    ;;
  esac
}

#======================================
# Say hello
#--------------------------------------
feedback title "ec2_builder launch script"
script_ver=$(grep '^# Version:[ \t]*' ${0} | sed 's|# Version:[ \t]*||')
hostos_pretty=$(grep '^PRETTY_NAME=' /etc/os-release | sed 's|"||g; s|^PRETTY_NAME=||;')
feedback body "Script: ${0}"
feedback body "Script version: ${script_ver}"
feedback body "OS: ${hostos_pretty}"
feedback body "User: $(whoami)"
feedback body "Shell: $(readlink /proc/$$/exe)"
feedback body "Started: $(date)"

#======================================
# Declare the constants
#--------------------------------------
# AWS CLI
if [ ! -f '/usr/bin/aws' ] && [ -f '/usr/bin/apt' ]
then
  # Assume AWS CLI is not installed and we have the apt package manager. AL2 includes AWS CLI by default but Ubuntu does not
  feedback h1 'Installing the awscli package'
  apt update
  apt --assume-yes install awscli
fi

feedback h1 'Setting up'

feedback h3 'Get the EC2 instance ID and AWS region'
# The initial AWS region setting using the instances placement so that we can connect to the AWS SSM parameter store
if [ -f '/usr/bin/ec2metadata' ]
then
  instance_id=$(ec2metadata --instance-id)
  aws_region=$(ec2metadata --availability-zone | cut -c 1-9)
elif [ -f '/usr/bin/ec2-metadata' ]
then
  instance_id=$(ec2-metadata --instance-id | cut -c 14-)
  aws_region=$(ec2-metadata --availability-zone | cut -c 12-20)
else
  feedback error "Can't find ec2metadata or ec2-metadata"
fi
if [ -z "${aws_region}" ]
then
  feedback error "AWS region not set, assuming us-east-1"
  aws_region='us-east-1'
fi
feedback body "Instance ${instance_id} is in the ${aws_region} region"

# What does the world around the instance look like
feedback body 'Get the tenancy and environment from the instance tags'
tenancy=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'tenancy'].Value" --output text --region ${aws_region})
resource_environment=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'resource_environment'].Value" --output text --region ${aws_region})
# Define the parameter store structure
common_parameters="/${tenancy}/${resource_environment}/common"
feedback body "Using AWS parameter store ${common_parameters} in the ${aws_region} region"

# Build script name
feedback body 'Get the name of the build app from the instance tags'
build_app=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'build_app'].Value" --output text --region ${aws_region})

# GitHub API secret
if [ -f '/usr/bin/aws' ]
then
  github_api_secret=$(aws ssm get-parameter --name "${common_parameters}/github/api_secret" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption)
else
  feedback error 'The awscli package is missing'
fi
if [ "${github_api_secret}" == "" ]
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
curl -H "Authorization: token ${github_api_secret}" \
     -H 'Accept: application/vnd.github.v4.raw' \
     -O \
     -f \
     -L \
     "https://raw.githubusercontent.com/mike548141/ec2_builder/master/${build_app}"
exit_code=${?}
if [ ${exit_code} -ne 0 ]
then
  feedback error "Error downloading the build script (${build_app}), curl error ${exit_code}"
else
  chmod 0740 "/root/${build_app}"
  feedback h2 'Execute the build script'
  "/root/${build_app}" go
fi
