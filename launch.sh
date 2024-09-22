#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.3.3 2024-09-22T15:22
# File:         launch.sh
# License:      GNU GPL v3
# Language:     bash
# Source:       https://github.com/mike548141/ec2_builder
#
# Description: This script is a bridge between an AWS EC2 Launch Template and the ec2_builder recipe that configures the instance for its role.
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

check_packages () {
  # Handle a list of multiple packages by looping through them
  for package in ${2}
  do
    # Lookup the package name if given a file name
    if [ $(echo ${package} | grep -i '\.deb$') ]
    then
      local pkg_name=$(dpkg --info ${package} | grep ' Package: ' | sed 's|^ Package: ||;')
    elif [ $(echo ${package} | grep -i '\.rpm$') ]
    then
      ## I should add support for RPM packages
      local pkg_name='oops TBC'
    else
      local pkg_name=${package}
    fi
    
    # Check if the package is listed in the package manger database
    local pkg_status=$(dpkg-query --showformat='${db:Status-Abbrev}' --show ${pkg_name})
    if [ "${1}" == "present" ] && [ ${pkg_status} != 'ii' ]
    then
      # Not installed i.e. not listed in the package manger database
      feedback error "The package ${pkg_name} has not installed properly (${pkg_status})"
    elif [ "${1}" == "absent" ] && [ ${pkg_status} == 'ii' ]
    then
      feedback error "The package ${pkg_name} is already installed (${pkg_status})"
    fi
  done
}

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

# Beautifies the feedback to std_out
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

# Install an application package
pkgmgr () {
  # Check that the package manager is not already running
  check_pid_lock ${packmgr}
  case ${1} in
  update)
    feedback h3 'Get updates from package repositories'
    case ${packmgr} in
    apt)
      apt-get --assume-yes update
      local exit_code=${?}
      ;;
    yum)
      yum --assumeyes update
      local exit_code=${?}
      ;;
    esac
    ;;
  upgrade)
    feedback h3 'Upgrade installed packages'
    case ${packmgr} in
    apt)
      apt-get --assume-yes upgrade
      local exit_code=${?}
      ;;
    yum)
      yum --assumeyes upgrade
      local exit_code=${?}
      ;;
    esac
    ;;
  install)
    # Check if any of the packages are already installed
    check_packages absent "${2}"
    feedback h3 "Install ${2}"
    case ${packmgr} in
    apt)
      apt-get --assume-yes install ${2}
      local exit_code=${?}
      ;;
    yum)
      yum --assumeyes install ${2}
      local exit_code=${?}
      ;;
    esac
    # Check that each of the packages are now showing as installed in the package database to verify it completed properly
    check_packages present "${2}"
    ;;
  *)
    feedback error "The package manager function can not understand the command ${1}"
    ;;
  esac
  if [ ${exit_code} -ne 0 ]
  then
    feedback error "${packmgr} exit code ${exit_code}"
  else
    feedback body "Thumbs up, ${packmgr} exit code ${exit_code}"
  fi
  # Wait for the package manager to terminate
  check_pid_lock ${packmgr}
}

what_is_instance_meta () {
  # AWS region and EC2 instance ID so we can use awscli
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
}

what_is_package_manager () {
  # Which package manger do we have to work with
  if [ -f '/usr/bin/apt' ]
  then
    packmgr='apt'
  elif [ -f '/usr/bin/yum' ]
  then
    packmgr='yum'
  else
    feedback error 'Package manager not found'
  fi
}

#======================================
# Say hello
#--------------------------------------
feedback title 'ec2_builder launch script'
feedback body "Script: ${0}"
feedback body "Script version: $(grep '^#[ \t]*Version:[ \t]*' ${0} | sed 's|#[ \t]*Version:[ \t]*||')"
feedback body "OS: $(grep '^PRETTY_NAME=' /etc/os-release | sed 's|"||g; s|^PRETTY_NAME=||;')"
feedback body "User: $(whoami)"
feedback body "Shell: $(readlink /proc/$$/exe)"
feedback body "Started: $(date)"

#======================================
# Declare the constants
#--------------------------------------
what_is_package_manager

what_is_instance_meta

#======================================
# Declare the variables
#--------------------------------------

#======================================
# Lets get into it
#--------------------------------------
feedback body "Instance ${instance_id} is in the ${aws_region} region"

feedback h1 'Updating and adding prerequisites'
pkgmgr update
pkgmgr install 'awscli git jq'

ec2_builder_repo=$(aws_info ec2_tag 'ec2_builder_repo')
recipe=$(aws_info ec2_tag 'recipe')

feedback h1 'Clone the build scripts'
mkdir --parents '~/builder/'
git clone ${ec2_builder_repo} '~/builder/'
exit_code=${?}
if [ ${exit_code} -ne 0 ]
then
  feedback error "Git error ${exit_code} cloning ${ec2_builder_repo}"
  exit 1
fi

feedback h1 "Start the ${recipe} recipe"
next_script=$(jq --raw-output ".inventory.recipes.${recipe}.init_script" ~/builder/inventory.json)
chmod 0740 ~/builder/${next_script}
~/builder/${next_script} launch
