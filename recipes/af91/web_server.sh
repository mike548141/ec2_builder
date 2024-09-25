#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.8.0 2024-09-23T01:59
# File:         web_server.sh
# License:      GNU GPL v3
# Language:     bash
# Source:       https://github.com/mike548141/ec2_builder
#
# Description:
#   Produces a cakeIT web server, developed on an Amazon Linux 2 (AL2) AMI using a t3a.nano instance. Extended to be built on Ubuntu as the primary platform with as much backwards compatibility to AL2 as possible.
#
# References:
#
# Pre-requisite:
#   The script is dependent upon its IAM role (arn:aws:iam::954095588241:role/ec2-web.cakeit.nz) and the IAM user (arn:aws:iam::954095588241:user/ec2.web2.cakeit.nz) for permissions
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
for ingredient in ~/builder/ingredients/*.sh
do
  source ${ingredient}
done

#======================================
# Say hello
#--------------------------------------
if [ "${1}" == "launch" ]
then
  feedback title 'ec2_builder build script'
  script_ver=$(grep '^# Version:[ \t]*' ${0} | sed 's|# Version:[ \t]*||')
  hostos_pretty=$(grep '^PRETTY_NAME=' '/etc/os-release' | sed 's|"||g; s|^PRETTY_NAME=||;')
  feedback body "Script: ${0}"
  feedback body "Script version: ${script_ver}"
  feedback body "OS: ${hostos_pretty}"
  feedback body "User: $(whoami)"
  feedback body "Shell: $(readlink /proc/$$/exe)"
  feedback body "Started: $(date)"
else
  feedback error 'Exiting because you did not use the special word'
  feedback body 'This is to protect against running this script unintentionally, it could cause damage to the host'
  feedback body "Run '${0} launch' to execute the script"
  exit 1
fi

#======================================
# Declare the constants
#--------------------------------------
aws_region_default='us-east-1'

# Get to know the OS so we can support AL2 and Ubuntu
hostos_id=$(grep '^ID=' '/etc/os-release' | sed 's|"||g; s|^ID=||;')
hostos_ver=$(grep '^VERSION_ID=' '/etc/os-release' | sed 's|"||g; s|^VERSION_ID=||;')

what_is_package_manager

what_is_instance_meta

#======================================
# Declare the variables
#--------------------------------------
tenancy=$(aws_info ec2_tag 'tenancy')
resource_environment=$(aws_info ec2_tag 'resource_environment')
service_group=$(aws_info ec2_tag 'service_group')
# Define the parameter store structure based on the meta we just grabbed
common_parameters="/${tenancy}/${resource_environment}/common"
app_parameters="/${tenancy}/${resource_environment}/${service_group}"

what_is_public_ip

#======================================
# Lets get into it
#--------------------------------------
feedback body "Instance ${instance_id} is using AWS parameter store ${app_parameters} in the ${aws_region} region"

app_fedora_epel

# Update the software stack
feedback h1 'Update the software stack'
pkgmgr update
pkgmgr upgrade
systemctl daemon-reload

feedback h1 'AWS EC2 instance tags'
aws_info ec2_tags

case ${packmgr} in
apt)
  # Debian (Ubuntu) tools to automate package installations that are interactive
  feedback h1 'Install package management extensions'
  pkgmgr install 'debconf-utils'
  ;;
esac

# Configure and secure the SSH daemon
app_sshd

app_sudo

# Create the local users on the host
## This should really link back to a central user repo and users get created dynamically when they login e.g. Google SAML IDP
feedback h1 'Create the user mike'
useradd --shell '/bin/bash' --create-home -c 'Mike Clements' --groups ssh,sudo 'mike'
feedback h3 'Add SSH key'
mkdir --parents '/home/mike/.ssh'
chmod 0700 '/home/mike/.ssh'
#wget --tries=2 -O '/home/mike/.ssh/authorized_keys' 'https://cakeit.nz/identity/mike.clements/mike-ssh.pub'
echo $(aws_info ssm "${common_parameters}/ssh/mike") > '/home/mike/.ssh/authorized_keys'
chmod 0600 '/home/mike/.ssh/authorized_keys'
chown -R mike:mike '/home/mike/.ssh'

feedback h1 'Systems management agent'
feedback body 'AWS SSM agent is already installed by default in the AMI'
pkgmgr install 'ansible'

# Install security apps
feedback h1 'Install security apps to protect the host'
pkgmgr install 'fail2ban'
app_rkhunter
app_tripwire
app_lsm
app_lsa
app_osquery

pam_google_mfa

# General tools
feedback h1 'Useful tools for Linux'
feedback h2 'AWS EC2 tools'
pkgmgr install 'ec2-ami-tools'
feedback h2 'Whole host use/performance'
pkgmgr install 'stacer sysstat nmon strace'
feedback h2 'CPU use/performance'
feedback h2 'Memory use/performance'
feedback h2 'Disk use/performance'
pkgmgr install 'iotop'
feedback h2 'Network configuration'
pkgmgr install 'ethtool'
feedback h2 'Network use/performance'
pkgmgr install 'iptraf-ng nethogs iftop bmon'
## iperf3
app_ookla_speedtest_client
feedback h2 'Database client'
app_mariadb_client

mount_efs_volume
# Import the common constants and variables held in a script on the EFS volume. This saves duplicating code between scripts
feedback h2 'Import the common variables from EFS'
source "${efs_mount_point}/script/common_variables.sh"

# Create users and groups for the vhosts on EFS
# The OS and base AMI packages use 0-1000 for the UID's and GID's they require. I have reserved 1001-2000 for UID's and GID's that are intrinsic to the build. UID & GID 2001 and above are for general use.
feedback h1 'Configure local users and groups to match those on EFS'
# Groups
feedback h3 'Create groups'
groupadd --gid 2001 vhost_all
groupadd --gid 2002 vhost_owners
groupadd --gid 2003 vhost_users
# Users
feedback h3 'Create users'
for vhost_dir in ${vhost_dir_list}
do
  if [ "${vhost_dir}" == "_default_" ] || [ "${vhost_dir}" == "example.com" ]
  then
    # These vhost directories don't need vhost users created
    feedback body "Skipping ${vhost_dir}"
  else
    # Create the owner accounts
    # Owner accounts exist to own the data & processes for the vhost, and (using their group) can delegate full access within a vhost to an end user
    vhost_dir_uid=$(stat -c '%u' "${vhost_root}/${vhost_dir}")
    vhost_dir_gid=$(stat -c '%g' "${vhost_root}/${vhost_dir}")
    feedback body "Creating owner ${vhost_dir} with UID/GID ${vhost_dir_uid}/${vhost_dir_gid} for ${vhost_root}/${vhost_dir}"
    groupadd --gid ${vhost_dir_gid} "${vhost_dir}"
    useradd --uid ${vhost_dir_uid} --gid ${vhost_dir_gid} --shell '/sbin/nologin' --home-dir "${vhost_root}/${vhost_dir}" --no-create-home --groups vhost_owners,vhost_all -c 'Web space owner' "${vhost_dir}"
  fi
done

configure_awscli

mount_s3_bucket

app_apache2

# Install Ghost Script, a PostScript interpreter and renderer that is used by WordPress for PDFs
pkgmgr install 'ghostscript'

app_mariadb_server

# Install scripting languages
feedback h1 'Install scripting languages'
pkgmgr install 'python3'
pkgmgr install 'golang'
pkgmgr install 'ruby'
pkgmgr install 'nodejs npm'
app_php

# Assign the EIP for web2 to this instance, this will remove the EIP from any running instance
associate_eip

# Create the DNS records for this instance
create_dns_record

# Create a certificate for this instance, and configure its PKI duties like certificate renewals
create_pki_certificate

app_ookla_speedtest_server

# Disable services we don't need
disable_service iscsi.service
disable_service iscsid.service
disable_service open-iscsi.service

# Grab warnings and errors to review
grep -i 'error' '/var/log/cloud-init-output.log' | sort | uniq >> ~/for_review.log
grep -i 'warn' '/var/log/cloud-init-output.log' | sort | uniq >> ~/for_review.log

# Thats all I wrote
feedback title "Build script finished - https://${instance_id}.${hosting_domain}/wiki/"
exit 0


#php 8
#EFS and S3 files missing
#speedtest
#ssh mike user
#cloudflare error
#trade out pkgmgr and apt for apt-get etc to stop WARNING: apt does not have a stable CLI interface. Use with caution in scripts.
#EC2 recommends setting IMDSv2 to required
