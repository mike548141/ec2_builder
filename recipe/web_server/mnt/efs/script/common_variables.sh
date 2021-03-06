#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.9-20210306
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
# Checks if the app is running, and waits for it to exit cleanly
check_pid_lock () {
  local sleep_timer=0
  local sleep_max_timer=90
  # Input error check for the function variables
  if [[ ${2} =~ [^0-9] ]]
  then
    feedback error "check_pid_lock Invalid timer specified, using default of ${sleep_max_timer}"
  elif [[ -n ${2} && ${2} -ge 0 && ${2} -le 3600 ]]
  then
    sleep_max_timer=${2}
  elif [[ -n ${2} ]]
  then
    feedback error "check_pid_lock Timer outside of 0-3600 range, using default of ${sleep_max_timer}"
  fi
  # Watches to see the process (pid) has terminated
  while [ -f "/var/run/${1}.pid" ]
  do
    if [[ ${sleep_timer} -ge ${sleep_max_timer} ]]
    then
      feedback error "Giving up waiting for ${1} to exit after ${sleep_timer} of ${sleep_max_timer} seconds"
      break
    elif [ $(ps -ef | grep -v 'grep' | grep "${1}" | wc -l) -ge 1 ]
    then
      feedback body "function timer: Waiting for ${1} to exit"
      sleep 1
      sleep_timer=$(( ${sleep_timer} + 1 ))
    else
      ## I should safety check this, make sure I'm not deleting the pid file with the process still running
      feedback error "Deleting the PID file for ${1} because the process is not running"
      rm --force "/var/run/${1}.pid"
      break
    fi
  done
}

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

# Install an app using yum
pkgmgr () {
  # Check that the package manager is not already running
  check_pid_lock ${packmgr}
  case ${1} in
  update)
    feedback h2 'Get updates from package repositories'
    case ${packmgr} in
    apt)
      apt update
      local exit_code=${?}
      ;;
    yum)
      yum --assumeyes update
      local exit_code=${?}
      ;;
    esac
    ;;
  upgrade)
    feedback h2 'Upgrade installed packages'
    case ${packmgr} in
    apt)
      apt --assume-yes upgrade
      local exit_code=${?}
      ;;
    yum)
      yum --assumeyes upgrade
      local exit_code=${?}
      ;;
    esac
    ;;
  install)
    feedback h2 "Install ${2}"
    case ${packmgr} in
    apt)
      apt --assume-yes install ${2}
      local exit_code=${?}
      ;;
    yum)
      yum --assumeyes install ${2}
      local exit_code=${?}
      ;;
    esac
    #### Check each package in the array was installed
    ;;
  *)
    feedback error "The package manager function can not understand the command ${1}"
    ;;
  esac
  if [ ${exit_code} -ne 0 ]
  then
    feedback error "${packmgr} exit code ${exit_code}"
  fi
  # Wait for the package manager to terminate
  check_pid_lock ${packmgr}
}

# Wrap the amazon_linux_extras script with additional steps
manage_ale () {
  case ${hostos_id} in
  amzn)
    amazon-linux-extras ${1} ${2}
    yum clean metadata
    ;;
  esac
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
hostos_pretty=$(grep '^PRETTY_NAME=' /etc/os-release | sed 's|"||g; s|^PRETTY_NAME=||;')

#======================================
# Declare the constants
#--------------------------------------
# Get to know the OS so we can support AL2 and Ubuntu
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

feedback body 'Get the service group'
service_group=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'service_group'].Value" --output text --region ${aws_region})
# Define the parameter store structure
app_parameters="/${tenancy}/${resource_environment}/${service_group}"

# Connect to AWS SSM Parameter Store to see what region we should be using
aws_region=$(aws ssm get-parameter --name "${app_parameters}/awscli/aws_region" --query 'Parameter.Value' --output text --region ${aws_region})

# The domain name used by the servers for web hosting, this domain name represents the hosting provider and not its customers vhosts
hosting_domain=$(aws ssm get-parameter --name "${app_parameters}/hosting_domain" --query 'Parameter.Value' --output text --region ${aws_region})
# The AWS EFS mount point used to hold virtual host config, content and logs that is shared between web hosts (aka instances)
efs_mount_point=$(aws ssm get-parameter --name "${app_parameters}/efs_mount_point" --query 'Parameter.Value' --output text --region ${aws_region})
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
