#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.2.0-20210306
# File:         common_variables.sh
# License:      GNU GPL v3
# Language:     bash
# Source:       https://github.com/mike548141/ec2_builder
#
# Description:
#  Sets a number of variables that other scripts rely upon.
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

# Find what Public IP addresses are assigned to the instance
get_public_ip () {
  if [ -f '/usr/bin/ec2metadata' ]
  then
    public_ipv4=$(ec2metadata --public-ipv4)
    ##public_ipv6=$(ec2metadata --public-ipv6 | cut -c 14-)
  elif [ -f '/usr/bin/ec2-metadata' ]
  then
    public_ipv4=$(ec2-metadata --public-ipv4 | cut -c 14-)
    ##public_ipv6=$(ec2-metadata --public-ipv6 | cut -c 14-)
  else
    feedback error "Can't find ec2metadata or ec2-metadata to find the public IP"
  fi
}

#======================================
# Say hello
#--------------------------------------
# Check if the script has already been run to save CPU cycles
if [ ! -z "${common_variables}" ]
then
  feedback body 'The common variables have already been set, skipping'
  exit 1
fi

#======================================
# Declare the constants
#--------------------------------------
# Get to know the OS so we can support AL2 and Ubuntu
hostos_pretty=$(grep '^PRETTY_NAME=' /etc/os-release | sed 's|"||g; s|^PRETTY_NAME=||;')
hostos_id=$(grep '^ID=' /etc/os-release | sed 's|"||g; s|^ID=||;')
hostos_ver=$(grep '^VERSION_ID=' /etc/os-release | sed 's|"||g; s|^VERSION_ID=||;')
if [ -f '/usr/bin/apt' ]
then
  packmgr='apt'
elif [ -f '/usr/bin/yum' ]
then
  packmgr='yum'
else
  feedback error 'Package manager not found'
fi

# The initial AWS region setting using the instances placement so that we can connect to the AWS SSM parameter store
if [ -f '/usr/bin/ec2metadata' ]
then
  aws_region=$(ec2metadata --availability-zone | cut -c 1-9)
  instance_id=$(ec2metadata --instance-id)
elif [ -f '/usr/bin/ec2-metadata' ]
then
  aws_region=$(ec2-metadata --availability-zone | cut -c 12-20)
  instance_id=$(ec2-metadata --instance-id | cut -c 14-)
else
  feedback error "Can't find ec2metadata or ec2-metadata"
fi
if [ -z "${aws_region}" ]
then
  aws_region='us-east-1'
  feedback error "AWS region not set, assuming ${aws_region}"
fi

tenancy=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'tenancy'].Value" --output text --region ${aws_region})
resource_environment=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'resource_environment'].Value" --output text --region ${aws_region})
service_group=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'service_group'].Value" --output text --region ${aws_region})
# Define the parameter store structure
common_parameters="/${tenancy}/${resource_environment}/common"
feedback body "Instance ${instance_id} is using AWS parameter store ${common_parameters} in the ${aws_region} region"

# Define the parameter store structure
app_parameters="/${tenancy}/${resource_environment}/${service_group}"
# The domain name used by the servers for web hosting, this domain name represents the hosting provider and not its customers vhosts
hosting_domain=$(aws ssm get-parameter --name "${app_parameters}/hosting_domain" --query 'Parameter.Value' --output text --region ${aws_region})
# The AWS EFS mount point used to hold virtual host config, content and logs that is shared between web hosts (aka instances)
efs_mount_point=$(aws ssm get-parameter --name "${app_parameters}/awsefs/mount_point" --query 'Parameter.Value' --output text --region ${aws_region})
# The AWS S3 bucket used to hold web content that is shared between web hosts, not currently used but is cheaper than EFS
s3_bucket=$(aws ssm get-parameter --name "${app_parameters}/s3fs/bucket" --query 'Parameter.Value' --output text --region ${aws_region})
# The AWS S3 mount point used to hold web content that is shared between web hosts, not currently used but is cheaper than EFS
s3_mount_point=$(aws ssm get-parameter --name "${app_parameters}/s3fs/mount_point" --query 'Parameter.Value' --output text --region ${aws_region})
# The root directory that all the vhosts folders are within
vhost_root=$(aws ssm get-parameter --name "${app_parameters}/vhost/root" --query 'Parameter.Value' --output text --region ${aws_region})
# The web servers config file that includes each of the individual vhosts
vhost_httpd_conf=$(aws ssm get-parameter --name "${app_parameters}/vhost/httpd_conf" --query 'Parameter.Value' --output text --region ${aws_region})
# A list of the vhosts that the web server loads e.g. cakeit.nz
vhost_list=$(grep -i '^Include ' ${vhost_httpd_conf} | sed "s|[iI]nclude \"${vhost_root}/||g; s|/conf/httpd.conf\"||g;")
# A list of the vhost folders stored, irrespective of if they are loaded by the web server or not
vhost_dir_list=$(ls --directory ${vhost_root}/*/ | sed "s|^${vhost_root}/||;s|/$||;")

#======================================
# Declare the variables
#--------------------------------------
get_public_ip

#======================================
# Lets get into it
#--------------------------------------
# Add a flag variable to show the script has already been run to save re-running it multiple times
common_variables="$(date)"
feedback body 'Common variables have been set'
