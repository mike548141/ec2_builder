#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.3.2-20210314
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
  case {1} in
  ec2_tag)
    return $(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == '${2}'].Value" --output text --region ${aws_region})
    ;;
  ssm)
    return $(aws ssm get-parameter --name "${2}" --query 'Parameter.Value' --output text --region ${aws_region})
    ;;
  ssm_secure)
    return $(aws ssm get-parameter --name "${2}" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption)
    ;;
  *)
    feedback error "aws_info function does not handle ${1}"
    ;;
  esac
}

check_packages () {
  # Handle a list of multiple packages by looping through them
  for one_pkg in ${2}
  do
    # Lookup the package name if given a file name
    if [ $(echo ${one_pkg} | grep -i '\.deb$') ]
    then
      local one_clean_pkg=$(dpkg --info ${one_pkg} | grep ' Package: ' | sed 's|^ Package: ||;')
    elif [ $(echo ${one_pkg} | grep -i '\.rpm$') ]
    then
      ## Add support for rpm packages
      local one_clean_pkg='oops TBC'
    else
      local one_clean_pkg=${one_pkg}
    fi
    
    # Check if the package is listed in the package manger database
    if [ -z "$(apt list --installed ${one_clean_pkg} | grep -v '^Listing')" ]
    then
      if [ "${1]" == "present" ]
      then
        feedback error "The package ${one_clean_pkg} has not installed properly"
      fi
    else
      if [ "${1]" == "absent" ]
      then
        feedback error "The package ${one_clean_pkg} is already installed"
      fi
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
ec2_builder_repo=$(aws_info ec2_tag 'ec2_builder_repo')
recipe=$(aws_info ec2_tag 'recipe')

#======================================
# Lets get into it
#--------------------------------------
feedback body "Instance ${instance_id} is in the ${aws_region} region"

feedback h1 'Updating and adding prerequisites'
pkgmgr update
pkgmgr install 'awscli git jq'

feedback h1 'Clone ec2_builder'
mkdir --parents ~/builder/
git clone "${ec2_builder_repo}" ~/builder/
exit_code=${?}
if [ ${exit_code} -ne 0 ]
then
  feedback error "Git error ${exit_code} cloning ${ec2_builder_repo}"
  exit 1
fi

feedback h1 "Launch the ${recipe} recipe"
next_script=$(jq ".inventory.recipes.${recipe}.init_script" ~/builder/inventory.json)
chmod 0740 ~/builder/${next_script}
~/builder/${next_script} go
