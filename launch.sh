#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.3.1-20210307
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
    feedback h3 'Upgrade installed packages'
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
    feedback h3 "Install ${2}"
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
    ;;
  *)
    feedback error "The package manager function can not understand the command ${1}"
    ;;
  esac
  if [ ${exit_code} -ne 0 ]
  then
    feedback error "${packmgr} exit code ${exit_code}"
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

#======================================
# Declare the variables
#--------------------------------------

#======================================
# Lets get into it
#--------------------------------------
feedback body "Instance ${instance_id} is in the ${aws_region} region"

feedback h1 'Add pre-reqs'
pkgmgr update
pkgmgr install 'awscli'
pkgmgr install 'git'

feedback h1 'Retrieve ec2_builder'
ec2_builder_repo=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'ec2_builder_repo'].Value" --output text --region ${aws_region})
cd ~
git clone ${ec2_builder_repo}
exit_code=${?}
if [ ${exit_code} -ne 0 ]
then
  feedback error "Git error ${exit_code} pulling ${ec2_builder_repo}"
  exit 1
fi

recipe=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'recipe'].Value" --output text --region ${aws_region})
feedback h1 "Launch the ${recipe} recipe"
chmod 0740 ~/ec2_builder/recipe/${recipe}.sh
~/ec2_builder/recipe/${recipe}.sh go
