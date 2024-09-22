#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.4.0 2024-09-22T23:16
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

#======================================
# Say hello
#--------------------------------------

echo ''
echo '*********************************************************************************'
echo '*                                                                               *'
echo '*   ec2_builder launch script                                                   *'
echo '*                                                                               *'
echo '*********************************************************************************'
echo "--> Script: ${0}"
echo "--> Script version: $(grep '^#[ \t]*Version:[ \t]*' ${0} | sed 's|#[ \t]*Version:[ \t]*||')"
echo "--> OS: $(grep '^PRETTY_NAME=' /etc/os-release | sed 's|"||g; s|^PRETTY_NAME=||;')"
echo "--> User: $(whoami)"
echo "--> Shell: $(readlink /proc/$$/exe)"
echo "--> Started: $(date)"

#======================================
# Declare the constants
#--------------------------------------
aws_region=$(ec2metadata --availability-zone | cut -c 1-9)
instance_id=$(ec2metadata --instance-id)

#======================================
# Declare the variables
#--------------------------------------

#======================================
# Lets get into it
#--------------------------------------
echo "--> Instance ${instance_id} is in the ${aws_region} region"
snap install aws-cli --classic

ec2_builder_repo=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'ec2_builder_repo'].Value" --output text --region "${aws_region}")
recipe=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'recipe'].Value" --output text --region "${aws_region}")

echo ''
echo '================================================================================'
echo '    Clone the build scripts'
echo '================================================================================'
echo ''
mkdir --parents ~/builder/
git clone ${ec2_builder_repo} ~/builder/
exit_code=${?}
if [ ${exit_code} -ne 0 ]
then
  feedback error "Git error ${exit_code} cloning ${ec2_builder_repo}"
  exit 1
fi
for ingredient in ~/builder/ingredients/*.sh
do
  source ${ingredient}
done

feedback h1 'AWS EC2 instance tags'
aws_info ec2_tags

feedback h1 "Start the ${recipe} recipe"
next_script=$(jq --raw-output ".inventory.recipes.${recipe}.init_script" ~/builder/inventory.json)
chmod 0740 ~/builder/${next_script}
~/builder/${next_script} launch
