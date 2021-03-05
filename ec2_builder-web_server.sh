#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.7.51-20210305
# File:         ec2_builder-web_server.sh
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
# * Should I switch to ubuntu? Ubuntu feels more capable than AL2 and keeps it inline with what I use on-prem
# * Do I get the tenancy, resource_environment, service_group etc from the AWS tags on the instance? Fewer values stored in the script & easily editable on the template. Also more reusable/accessible values as tags from both within the instance and from other AWS services
#   * Need a shared user directory for end users (aka customers)
# Create the end user accounts, these user accounts are used to login (e.g. using SSH) to manage a vhost and will generally represent a real person.
## end users is for customers that actually login via services (e.g. web portal/API etc) or shell (SSH/SCP etc)
# Get the list of end users from the PKI/SSH keys in vhost/pki?
# Would be even better if end users used OpenID or oAuth so no credenditals are stored here... Better UX as fewer passwords etc.
# Not sure if I should/need to specify the UID for end users or leave it to fate
# End users will need to be a member of the vhost's owner group e.g. mike would be a member of cakeit.nz & competitiveedge.nz which are the primary groups of the vhost owners... A user must be able to be a member of many vhosts with one user ID
#useradd --uid ${end_user_uid} --gid ${end_user_gid} --home-dir "${vhost_root}/${vhost_dir}" --groups vhost_users,vhost_all,${vhost_dir} "${end_user}"
# Must be able to add a user to a owners group to give them access and it sticks (not lost when scripts run to build/update instances). Ant remain consistent across all instances
# Extend script to delete or disable existing users?  Maybe disable all users in vhost_users and then re-enable if directory still exists?
# Do I even need to disable as no password? Depend on user ID & SSH/PKI token?
#
#   * Do I use PGP instead of PKI to verify end users? e.g. yum install monkeysphere
#   * Keep all temporal data with vhost e.g. php session and cache data. And configure PHP security features like chroot
#   * Ensure that when Lets Encrypt renews a vhosts certificate that it stores the latest versions on EFS with the vhost, not on EBS
#   * Configure a local DB, Aurora Serverless resume is too slow (~25s)
#   * Import my confluence download and any other info into the wiki
#   * Add support to run both PHP 5 and 7
#     - https://stackoverflow.com/questions/42696856/running-two-php-versions-on-the-same-server
#     - https://stackoverflow.com/questions/45033511/how-to-select-php-version-5-and-7-per-virtualhost-in-apache-2-4-on-debian
#   * Automate backups of web data (config, DB & files) at the same timestamp to allow easy recovery
#
#   * Move websites to web2
#
#   * Run the processes that are specific to a vhost as its own user. Q-Username should be domain name or a cn like competitive_edge?
#   * Configure security apps for defense in depth, take ideas from my suse studio scripts
#   * Add self-testing and self-healing to the build script to make sure everything is built and working properly e.g. did the DNS record create successfully
#
#   * SES for mail relay? So don't need SMTP out from server
#   * Install Tomcat?
#   * Static web data on S3, use a shared bucket to keep admin easy. Ideal would be a bucket per customer for security.
#
#   * Upgrade to load balancing the web serving work across 2 or more instances
#   * Upgrade to multi-AZ, or even multi-region for all components.
#   * Move to a multi-account structure using AWS Organisations. Use AWS CloudFormer to define all the resources in a template.
#   * Create CloudFormation templates for all the AWS resources so that the entire setup can be created fresh in new AWS accounts
#   * Is there a way to make the AWS AMI (Amazon Linux 2) as read only base, and all writes from this script, users logging in, or system use (e.g. logging) are written to a 2nd EBS volume?
#
#   * Get all S3 data into right storage tier. Files smaller than ?128KB? on S3IA or S3. Data larger than that in Deep Archive. Check inventory files.
#
#   * Can I shrink the EBS volume, its 8 GB but using 2.3GB
#   * Launch instance has a mount EFS volume option, is this better than what I have scripted? Can't find option in launch template
#
#   * Need event based host management system to issue commands to instances, don't use cron as wasted CPU cycles, increased risk of faliure, more complex code base etc
#     - Have HTTPD & PHP reload the config after changing a vhost e.g. systemctl restart httpd php-fpm
#     - add/delete users, groups, and group members as required. Ideally users & groups would be on a directory service
#   * Ideally this would use IAM users to support MFA and a user ID that could tie to other services e.g. a S3 bucket dedicated to a IAM user
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
  check_pid_lock ${hostos_pkgmgr}
  case ${1} in
  update)
    feedback h2 'Package manager update'
    case ${hostos_pkgmgr} in
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
    case ${hostos_pkgmgr} in
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
    case ${hostos_pkgmgr} in
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
    feedback error "${hostos_pkgmgr} exit code ${exit_code}"
  fi
  # Wait for the package manager to terminate
  check_pid_lock ${hostos_pkgmgr}
}
## I don't really want this type of error handling anymore but the code is useful reference
#feedback body 'Retrying install in 60 seconds'
#sleep 60
#feedback h3 'Running yum-complete-transaction -y'
#yum-complete-transaction -y
#exit_code=${?}
#feedback body "Exit code ${exit_code}"
#feedback h3 'Running yum history redo last'
#yum history redo last
#exit_code=${?}
#feedback body "Exit code ${exit_code}"
#feedback h3 'Running yum clean all'
#yum clean all
#exit_code=${?}
#feedback body "Exit code ${exit_code}"
#feedback h3 "Running yum --assumeyes install ${2}"
#yum --assumeyes install ${2}
#exit_code=${?}
#feedback body "Exit code ${exit_code}"

# Wrap the amazon_linux_extras script with additional steps
manage_ale () {
  if [ "${hostos_id}" == 'amzn' ]
  then
    amazon-linux-extras ${1} ${2}
    yum clean metadata
  fi
}

#======================================
# Say hello
#--------------------------------------
if [ "${1}" == "go" ]
then
  feedback title "ec2_builder build script"
  script_ver=$(grep '^# Version:[ \t]*' ${0} | sed 's|# Version:[ \t]*||')
  hostos_pretty=$(grep '^PRETTY_NAME=' /etc/os-release | sed 's|"||g; s|^PRETTY_NAME=||;')
  feedback body "Script: ${0}"
  feedback body "Script version: ${script_ver}"
  feedback body "OS: ${hostos_pretty}"
  feedback body "User: $(whoami)"
  feedback body "Shell: $(readlink /proc/$$/exe)"
  feedback body "Started: $(date)"
else
  feedback error 'Exiting because you did not use the special word'
  feedback body 'This is to protect against running this script unintentionally, it could cause damage to the host'
  feedback body "Run '${0} go' to execute the script"
  exit 1
fi

#======================================
# Declare the constants
#--------------------------------------
# Get to know the OS so we can support AL2 and Ubuntu
hostos_id=$(grep '^ID=' /etc/os-release | sed 's|"||g; s|^ID=||;')
hostos_ver=$(grep '^VERSION_ID=' /etc/os-release | sed 's|"||g; s|^VERSION_ID=||;')
if [ -f '/usr/bin/apt' ]
then
  hostos_pkgmgr='apt'
elif [ -f '/usr/bin/yum' ]
then
  hostos_pkgmgr='yum'
else
  feedback error 'Package manager not found'
fi

# AWS CLI
if [ ! -f '/usr/bin/aws' ]
then
  # Assume AWS CLI is not installed and we have the apt package manager. AL2 includes AWS CLI by default but Ubuntu does not
  feedback h1 'Installing the awscli package'
  pkgmgr update
  pkgmgr install 'awscli'
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
if [ "${aws_region}" == '' ]
then
  feedback error "AWS region not set, assuming us-east-1"
  aws_region='us-east-1'
fi
feedback body "Instance ${instance_id} is in the ${aws_region} region"

# Configuration parameters are held in AWS Systems Manager Parameter Store, retrieving these using the AWC CLI. Permissions are granted to do this using a IAM role assigned to the instance
# Delete the AWS credentials file so that the AWS CLI uses the instances profile/role permissions
if [ -f '/root/.aws/credentials' ]
then
  rm --force '/root/.aws/credentials'
fi

# What does the world look like around the instance
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
app_parameters="/${tenancy}/${resource_environment}/${service_group}/${build_app}"

# Connect to AWS SSM Parameter Store to see what region we should be using
aws_region=$(aws ssm get-parameter --name "${app_parameters}/awscli/aws_region" --query 'Parameter.Value' --output text --region ${aws_region})

#======================================
# Declare the variables
#--------------------------------------
get_public_ip

#======================================
# Lets get into it
#--------------------------------------
# Add access to Extra Packages for Enterprise Linux (EPEL) from the Fedora project
if [ "${hostos_id}" == 'amzn' ]
then
  feedback h1 'Add access to Extra Packages for Enterprise Linux (EPEL) from the Fedora project'
  manage_ale enable 'epel'
  pkgmgr install 'epel-release'
fi

# Update the software stack
feedback h1 'Update the software stack'
pkgmgr update
pkgmgr upgrade
systemctl daemon-reload

# Configure the OpenSSH server
feedback h1 'Harden the OpenSSH daemon'
if [ ! $(getent group ssh_keys) ]
then
  feedback h3 'Create a group called ssh_keys'
  groupadd ssh_keys
fi
# New host keys incase they are compromised
feedback h3 'Re-generate the RSA and ED25519 keys'
rm --force /etc/ssh/ssh_host_*
ssh-keygen -t rsa -b 4096 -f '/etc/ssh/ssh_host_rsa_key' -N ""
chown root:ssh_keys '/etc/ssh/ssh_host_rsa_key'
chmod 0600 '/etc/ssh/ssh_host_rsa_key'
ssh-keygen -t ed25519 -f '/etc/ssh/ssh_host_ed25519_key' -N ""
chown root:ssh_keys '/etc/ssh/ssh_host_ed25519_key'
chmod 0600 '/etc/ssh/ssh_host_ed25519_key'
# Harden the server: small Diffie-Hellman are weak
feedback h3 'Remove small Diffie-Hellman moduli'
cp '/etc/ssh/moduli' '/etc/ssh/moduli.bak'
awk '$5 >= 3071' '/etc/ssh/moduli' > '/etc/ssh/moduli.safe'
mv -f '/etc/ssh/moduli.safe' '/etc/ssh/moduli'
# Harden the server: DSA and ECDSA host keys can't be trusted
feedback h3 'Disable the DSA and ECDSA host keys'
cp '/etc/ssh/sshd_config' '/etc/ssh/sshd_config.bak'
sed -i 's|^HostKey /etc/ssh/ssh_host_dsa_key$|#HostKey /etc/ssh/ssh_host_dsa_key|g' '/etc/ssh/sshd_config'
sed -i 's|^HostKey /etc/ssh/ssh_host_ecdsa_key$|#HostKey /etc/ssh/ssh_host_ecdsa_key|g' '/etc/ssh/sshd_config'
# Child configs for SSHD
mkdir --parents /etc/ssh/sshd_config.d/
if [ -z "$(grep -v '.*#' '/etc/ssh/sshd_config' | grep -i 'Include \/etc\/ssh\/sshd_config\.d\/\*\.conf')" ]
then
  ## Ubuntu has this by default, AL2's version of openssh-server (7.4p1-21.amzn2.0.1) does not support it
  echo '#Include /etc/ssh/sshd_config.d/*.conf' >> '/etc/ssh/sshd_config'
fi
# Use the cipher tech that we trust, tested against https://www.sshaudit.com/
feedback h3 'Restrict the key exchanges, ciphers, and MAC algorithms supported'
cat <<***EOF*** > '/etc/ssh/sshd_config.d/kecm.conf'
# Restrict key exchange, cipher, and MAC algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
***EOF***
# Harden the server: General config
feedback h3 'Restrict client connection config'
cat <<***EOF*** > '/etc/ssh/sshd_config.d/harden.conf'
Protocol 2

PubkeyAuthentication yes
AuthenticationMethods publickey

ClientAliveInterval 300
ClientAliveCountMax 24

LoginGraceTime 1m
PermitRootLogin no
StrictModes yes
MaxAuthTries 2
MaxSessions 10

PasswordAuthentication no
PermitEmptyPasswords no

PrintLastLog yes

Banner /etc/ssh/sshd-banner
***EOF***
# Banner
cat <<***EOF*** > '/etc/ssh/sshd-banner'

************************************************************************************************************************************************
*                                                                                                                                              *
* Use of this system is monitored and logged, unauthorised access is prohibited and is subject to criminal and civil penalties.                *
* By proceeding you consent to interception, auditing, and the interrogation of your devices, traffic and information for evidence of mis-use. *
*                                                                                                                                              *
************************************************************************************************************************************************

***EOF***
feedback h3 'Restart OpenSSH server'
systemctl restart sshd.service
systemctl -l status sshd.service

# Create the local users on the host
## This should really link back to a central user repo and users get created dynamically
feedback h1 'Create the user mike and a home directory'
useradd --create-home -c 'Mike Clements' 'mike'
feedback h3 'Add to sudoers'
usermod -aG 'sudo' 'mike'
feedback h3 'Add SSH key'
mkdir --parents '/home/mike/.ssh'
chown mike:mike '/home/mike/.ssh'
chmod 0700 '/home/mike/.ssh'
wget --tries=2 -O '/home/mike/.ssh/authorized_keys' 'https://cakeit.nz/identity/mike.clements/mike-ssh.pub'
chmod 0600 '/home/mike/.ssh/authorized_keys'

# Additional AWS EC2 tools, only applicable to Ubuntu
feedback h1 'Install AWS tools'
pkgmgr install 'ec2-ami-tools'

# Install the management agents
feedback h1 'System management agents'
# The AWS SSM agent is installed by default on both AL2 and Ubuntu (as a snap package) AMI's
# These packages are not required
#manage_ale enable 'ansible2'
#pkgmgr install 'ansible'
#manage_ale enable 'rust1'
#pkgmgr install 'rust cargo'
#pkgmgr install 'chef'
#pkgmgr install 'puppet'
#pkgmgr install 'salt'

# Install security apps
feedback h1 'Install security apps to protect the host'
pkgmgr install 'fail2ban'
pkgmgr install 'rkhunter'
### remove ui prompts
pkgmgr install 'tripwire'
# SELinux
pkgmgr install 'policycoreutils'
if [ "${hostos_id}" == 'ubuntu' ]
then
  pkgmgr install 'selinux-basics'
  selinux-activate
elif [ "${hostos_id}" == 'amzn' ]
then
  pkgmgr install 'policycoreutils-python selinux-policy selinux-policy-targeted'
fi
sestatus
# By installing the plugins package it will pull in the relevant package for Linux system auditing i.e. auditd for Ubuntu and audit for AL2
pkgmgr install 'audispd-plugins'
# OS Query
feedback h3 'Add the osquery repo and trust the GPG key'
case ${hostos_pkgmgr} in
apt)
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 1484120AC4E9F8A1A577AEEE97A80C63C9D8B80B
  add-apt-repository 'deb [arch=amd64] https://pkg.osquery.io/deb deb main'
  ;;
yum)
  curl -L https://pkg.osquery.io/rpm/GPG | sudo tee /etc/pki/rpm-gpg/RPM-GPG-KEY-osquery
  rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-osquery
  yum-config-manager --add-repo https://pkg.osquery.io/rpm/osquery-s3-rpm.repo
  yum-config-manager --enable osquery-s3-rpm
  ;;
esac
pkgmgr update
pkgmgr install 'osquery'

# Google Authenticator adds MFA capability to PAM - https://aws.amazon.com/blogs/startups/securing-ssh-to-amazon-ec2-linux-hosts/
feedback h1 'Google Authenticator to support MFA'
pkgmgr install 'google-authenticator'

# General tools
feedback h1 'General tools'
# Network tools
pkgmgr install 'ethtool'
# System monitoring
pkgmgr install 'stacer sysstat iotop'
# Install the MariaDB client for connecting to Aurora Serverless to manage the databases
pkgmgr install 'mariadb'
# Ookla speedtest client
feedback h2 'Ookla client repo'
case ${hostos_pkgmgr} in
apt)
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 379CE192D401AB61
  echo "deb https://ookla.bintray.com/debian generic main" | sudo tee  /etc/apt/sources.list.d/speedtest.list
  ;;
yum)
  wget --tries=2 https://bintray.com/ookla/rhel/rpm -O bintray-ookla-rhel.repo
  mv bintray-ookla-rhel.repo /etc/yum.repos.d/
  ;;
esac
pkgmgr update
pkgmgr install 'speedtest'
### check this installs properly

# Install AWS EFS helper and mount the EFS volume for vhost data
feedback h1 'AWS EFS helper'
pkgmgr install 'amazon-efs-utils'
feedback h3 'Mount the EFS volume for vhost data'
# The AWS EFS volume and mount point used to hold virtual host config, content and logs that is shared between web hosts (aka instances)
efs_volume=$(aws ssm get-parameter --name "${app_parameters}/efs_volume" --query 'Parameter.Value' --output text --region ${aws_region})
efs_mount_point=$(aws ssm get-parameter --name "${app_parameters}/efs_mount_point" --query 'Parameter.Value' --output text --region ${aws_region})
mkdir --parents ${efs_mount_point}
if mountpoint -q ${efs_mount_point}
then
  umount ${efs_mount_point}
fi
mount -t efs -o tls ${efs_volume}:/ ${efs_mount_point}
feedback body 'Set it to auto mount at boot'
cat <<***EOF*** >> '/etc/fstab'
# Mount AWS EFS volume ${efs_volume} for the web root data
${efs_volume}:/ ${efs_mount_point} efs tls,_netdev 0 0
***EOF***

# Import the common constants and variables held in a script on the EFS volume. This saves duplicating code between scripts
feedback h1 'Import the common constants and variables from EFS'
source "${efs_mount_point}/script/common_variables.sh"

# Create a directory for this instances log files on the EFS volume
### Probably remove this section above, should not be used anymore but need to check that
feedback h1 'Create a space for this instances log files on the EFS volume'
mkdir --parents "${vhost_root}/_default_/log/${instance_id}.${hosting_domain}"

# Create users and groups for the vhosts on EFS
# The OS and base AMI packages use 0-1000 for the UID's and GID's they require. I have reserved 1001-2000 for UID's and GID's that are intrinsic to the build. UID & GID 2001 and above are for general use.
feedback h1 'Configure local users and groups to match those on EFS'
# Groups
feedback h3 'Create groups'
groupadd --gid 1001 vhost_all
groupadd --gid 1002 vhost_owners
groupadd --gid 1003 vhost_users
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
    useradd --uid ${vhost_dir_uid} --gid ${vhost_dir_gid} --shell /sbin/nologin --home-dir "${vhost_root}/${vhost_dir}" --no-create-home --groups vhost_owners,vhost_all "${vhost_dir}"
  fi
done

# Default config for AWS CLI tools
feedback h1 'Configure AWS CLI for the root user'
aws_cli_output=$(aws ssm get-parameter --name "${app_parameters}/awscli/aws_cli_output" --query 'Parameter.Value' --output text --region ${aws_region})
aws configure set region ${aws_region}
aws configure set output ${aws_cli_output}

# Install Fuse S3FS and mount the S3 bucket for web server data - https://github.com/s3fs-fuse/s3fs-fuse
feedback h1 'Fuse S3FS'
pkgmgr install 's3fs-fuse'
feedback h3 'Configure FUSE'
sed -i 's|^# user_allow_other$|user_allow_other|' /etc/fuse.conf
feedback h3 'Configure AWS CLI credentials for the root user, S3FS uses the same file'
# This AWS API key and secret is attached to the IAM user ec2.web.cakeit.nz
aws_access_key_id=$(aws ssm get-parameter --name "${common_parameters}/awscli/aws_access_key_id" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption)
aws_access_key_secret=$(aws ssm get-parameter --name "${common_parameters}/awscli/aws_access_key_secret" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption)
aws configure set aws_access_key_id ${aws_access_key_id}
aws configure set aws_secret_access_key ${aws_access_key_secret}
# Clear the secret from memory
unset aws_access_key_id
unset aws_access_key_secret
feedback h3 'Mount the S3 bucket for static web data'
# The AWS S3 bucket used to hold web content that is shared between web hosts, not currently used but is cheaper than EFS
s3_bucket=$(aws ssm get-parameter --name "${app_parameters}/s3_bucket" --query 'Parameter.Value' --output text --region ${aws_region})
s3_mount_point=$(aws ssm get-parameter --name "${app_parameters}/s3_mount_point" --query 'Parameter.Value' --output text --region ${aws_region})
mkdir --parents ${s3_mount_point}
if mountpoint -q ${s3_mount_point}
then
  umount ${s3_mount_point}
fi
s3fs ${s3_bucket} ${s3_mount_point} -o allow_other -o use_path_request_style
feedback body 'Set it to auto mount at boot'
cat <<***EOF*** >> '/etc/fstab'
# Mount AWS S3 bucket ${s3_bucket} for static web data
s3fs#${s3_bucket} ${s3_mount_point} fuse _netdev,allow_other,use_path_request_style 0 0
***EOF***

# Install scripting languages
feedback h1 'Install scripting languages'
pkgmgr install 'python python3'
pkgmgr install 'golang'
pkgmgr install 'ruby'
pkgmgr install 'nodejs'
# PHP
manage_ale enable 'php7.3'
pkgmgr install 'php-cli php-pdo php-fpm php-json php-mysqlnd php-common'
# Customise the PHP config
pkgmgr install 'php-bcmath php-gd php-intl php-mbstring php-pecl-apcu php-pecl-imagick php-pecl-libsodium php-pecl-zip php-xml'
# Create a PHP config for the _default_ vhost
feedback h3 'Create a PHP-FPM config on EBS for this instances _default_ vhost'
cp "${vhost_root}/_default_/conf/instance-specific-php-fpm.conf" /etc/php-fpm.d/this-instance.conf
sed -i "s|i-.*\.cakeit\.nz|${instance_id}.${hosting_domain}|g" /etc/php-fpm.d/this-instance.conf
# Include the vhost config on the EFS volume
feedback h3 'Include the vhost config on the EFS volume'
cat <<***EOF*** > '/etc/php-fpm.d/vhost.conf'
; Include the vhosts stored on the EFS volume
include=${efs_mount_point}/conf/vhosts-php-fpm.conf
***EOF***
feedback h3 'Restart PHP-FPM to recognise the additional PHP modules and config'
systemctl restart php-fpm.service
systemctl -l status php-fpm.service

# Install MariaDB server to host databases as Aurora Serverless resume is too slow (~25s from cold to warm)
# This section will only be used for standalone installs. Eventually this will either use a dedicated EC2 running MariaDB or AWS RDS Aurora
feedback h1 'MariaDB (MySQL) server'
pkgmgr install 'mariadb-server'
###
feedback error 'Not starting the database server. Code disabled as its causing yum issues (DB corruption, failed install) for the build script'
#feedback h3 'Sleep for 5 seconds as the database server wont start immediately after install'
#sleep 5
#feedback h3 'Start the database server'
#systemctl restart mariadb
feedback body 'Set it to auto start at boot'
systemctl enable mariadb

# Install the web server
feedback h1 'Install the web server'
manage_ale enable 'httpd_modules'
pkgmgr install 'httpd mod_ssl'
feedback h3 'Start the web server'
systemctl restart httpd
feedback body 'Set it to auto start at boot'
systemctl enable httpd
# Customise the web server
feedback h2 'Customise the web server config'
# Install extra modules
feedback h3 'Install additional Apache HTTPD modules'
case ${hostos_pkgmgr} in
apt)
  pkgmgr install 'https://dl-ssl.google.com/dl/linux/direct/mod-pagespeed-stable_current_amd64.deb'
  ;;
yum)
  pkgmgr install 'https://dl-ssl.google.com/dl/linux/direct/mod-pagespeed-stable_current_x86_64.rpm'
  ;;
esac
# Replace the Apache HTTPD MPM module prefork with the module event for HTTP/2 compatibility and to improve server performance
feedback h3 'Change MPM modules from prefork to event'
cp '/etc/httpd/conf.modules.d/00-mpm.conf' '/etc/httpd/conf.modules.d/00-mpm.conf.bak'
sed -i 's|^LoadModule mpm_prefork_module modules/mod_mpm_prefork\.so$|#LoadModule mpm_prefork_module modules/mod_mpm_prefork.so|' /etc/httpd/conf.modules.d/00-mpm.conf
sed -i 's|^#LoadModule mpm_event_module modules/mod_mpm_event\.so$|LoadModule mpm_event_module modules/mod_mpm_event.so|' /etc/httpd/conf.modules.d/00-mpm.conf
# Disable the _default_ SSL config as it will be in the server specific config
feedback h3 'Disable the default SSL config'
mv '/etc/httpd/conf.d/ssl.conf' '/etc/httpd/conf.d/ssl.conf.disable'
# Disable the welcome page config
feedback h3 'Disable the welcome page config'
mv '/etc/httpd/conf.d/welcome.conf' '/etc/httpd/conf.d/welcome.conf.disable'
# Create a config for the server on the EBS volume
feedback h3 'Create a _default_ virtual host config on this instance'
cp "${vhost_root}/_default_/conf/instance-specific-httpd.conf" /etc/httpd/conf.d/this-instance.conf
sed -i "s|i-instanceid\.cakeit\.nz|${instance_id}.${hosting_domain}|g" /etc/httpd/conf.d/this-instance.conf
# Include the vhost config on the EFS volume
feedback h3 'Include the vhost config from the EFS volume'
cat <<***EOF*** > '/etc/httpd/conf.d/vhost.conf'
# Publish the vhosts stored on the EFS volume
Include ${vhost_httpd_conf}
***EOF***
# The vhosts httpd config points to this conf file, it won't exist yet since LetsEncrypt has not run yet. This creates an empty file so that httpd can load.
if [ ! -f '/etc/letsencrypt/options-ssl-apache.conf' ]
then
  feedback h3 'Create an empty options-ssl-apache.conf because the vhosts depend upon it'
  mkdir '/etc/letsencrypt'
  touch '/etc/letsencrypt/options-ssl-apache.conf'
fi
feedback h3 'Restart the web server'
systemctl restart httpd.service
feedback h3 'Web server status'
systemctl -l status httpd.service

feedback h1 'Web hosting software'
# Install Ghost Script, a PostScript interpreter and renderer that is used by WordPress for PDFs
pkgmgr install 'ghostscript'
# Install Git to support content versioning in MediaWiki
pkgmgr install 'git'

# Get the AWS Elastic IP address used to web host
eip_allocation_id=$(aws ssm get-parameter --name "${app_parameters}/eip_allocation_id" --query 'Parameter.Value' --output text --region ${aws_region})
# If the variable is blank then don't assign an EIP, assume there is a load balancer instead
if [ -z "${eip_allocation_id}" ]
then
  # Allocate the AWS EIP to this instance
  feedback h1 'Allocate the EIP public IP address to this instance'
  # Allocate the EIP
  aws ec2 associate-address --instance-id ${instance_id} --allocation-id ${eip_allocation_id} --region ${aws_region}
  # Update the public IP address assigned now the EIP is associated
  feedback body 'Sleep for 5 seconds to allow metadata to update after the EIP association'
  sleep 5
  get_public_ip
  feedback body "EIP address ${public_ipv4} associated"
fi

# Create a DNS entry for the web host
feedback h1 'Create a DNS entry on Cloudflare for this instance'
# Cloudflare API secret
cloudflare_zoneid=$(aws ssm get-parameter --name "${common_parameters}/cloudflare/${hosting_domain}/zone_id" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption)
cloudflare_api_token=$(aws ssm get-parameter --name "${common_parameters}/cloudflare/${hosting_domain}/api_token" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption)
curl -X POST "https://api.cloudflare.com/client/v4/zones/${cloudflare_zoneid}/dns_records" \
     -H "Authorization: Bearer ${cloudflare_api_token}" \
     -H "Content-Type: application/json" \
     --data '{"type":"A","name":"'"${instance_id}"'","content":"'"${public_ipv4}"'","ttl":1,"priority":10,"proxied":false}'
##curl -X POST "https://api.cloudflare.com/client/v4/zones/${cloudflare_zoneid}/dns_records" \
##     -H "Authorization: Bearer ${cloudflare_api_token}" \
##     -H "Content-Type: application/json" \
##     --data '{"type":"AAAA","name":"'"${instance_id}"'","content":"'"${public_ipv6}"'","ttl":1,"priority":10,"proxied":false}'
# Clear the secret from memory
unset cloudflare_api_token
feedback h3 'Sleeping for 5 seconds to allow that DNS change to replicate'
sleep 5

# Install Let's Encrypt CertBot
feedback h1 'Lets Encrypt CertBot'
pkgmgr install 'certbot python2-certbot-apache'
# Create and install this instances certificates, these will be kept locally on EBS.  All vhost certificates need to be kept on EFS.
feedback h2 'Get Lets Encrypt certificates for this server'
# The contact email address for Lets Encrypt if a certificate problem comes up
pki_email=$(aws ssm get-parameter --name "${app_parameters}/pki_email" --query 'Parameter.Value' --output text --region ${aws_region})
mkdir --parents "/var/log/letsencrypt"
certbot certonly --domains "${instance_id}.${hosting_domain},web2.${hosting_domain}" --apache --non-interactive --agree-tos --email "${pki_email}" --no-eff-email --logs-dir "/var/log/letsencrypt" --redirect --must-staple --staple-ocsp --hsts --uir

# Customise the _default_ vhost config to include the new certificate created by certbot
if [ -f "/etc/letsencrypt/live/${instance_id}.${hosting_domain}/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/${instance_id}.${hosting_domain}/privkey.pem" ]
then
  feedback h3 'Add the certificates to the web server config'
  ### Check this sed works
  sed -i "s|[^#]SSLCertificateFile| #SSLCertificateFile|g; \
          s|[^#]SSLCertificateKeyFile| #SSLCertificateKeyFile|g; \
          s|#SSLCertificateFile[ \t]*/etc/letsencrypt/live/|SSLCertificateFile\t\t/etc/letsencrypt/live/|; \
          s|#SSLCertificateKeyFile[ \t]*/etc/letsencrypt/live/|SSLCertificateKeyFile\t\t/etc/letsencrypt/live/|;" '/etc/httpd/conf.d/this-instance.conf'
  feedback h3 'Restart the web server'
  systemctl restart httpd
fi
# Link each of the vhosts listed in vhosts-httpd.conf to letsencrypt on this instance. So that all instances can renew all certificates as required
feedback h3 'Include the vhosts Lets Encrypt config on this server'
source "${efs_mount_point}/script/update_instance-vhosts_pki.sh"
# Add a job to cron to run certbot regularly for renewals and revocations
feedback h3 'Add a job to cron to run certbot daily'
cat <<***EOF*** > '/etc/cron.daily/certbot'
#!/usr/bin/env bash

# Update this instances configuration including what certificates need to be renewed
${efs_mount_point}/script/update_instance-vhosts_pki.sh

# Run Lets Encrypt Certbot to revoke and/or renew certiicates
certbot renew --no-self-upgrade
***EOF***
chmod 0770 /etc/cron.daily/certbot
systemctl restart crond

# Install Ookla Speedtest server
feedback h1 'Ookla speedtest server'
mkdir --parents '/opt/ookla/server'
cd /opt/ookla/server/
wget --tries=2 http://install.speedtest.net/ooklaserver/stable/OoklaServer.tgz
tar -xzvf OoklaServer.tgz OoklaServer-linux64.tar
rm --force OoklaServer.tgz
tar -xzvf OoklaServer-linux64.tar
rm --force OoklaServer-linux64.tar
chown root:root /opt/ookla/server/*
# Customise the config
sed -i 's|^logging\.loggers\.app\.|#logging.loggers.app.|g' /opt/ookla/server/OoklaServer.properties.default
cat <<***EOF*** >> '/opt/ookla/server/OoklaServer.properties.default'

# Server config
logging.loggers.app.name = Application
logging.loggers.app.channel.class = FileChannel
logging.loggers.app.channel.pattern = %Y-%m-%d %H:%M:%S [%P - %I] [%p] %t
logging.loggers.app.channel.path = /var/log/ooklaserver
logging.loggers.app.level = information
***EOF***
# Configure a daemon for systemd
cat <<***EOF*** > '/opt/ookla/server/ookla-server.service'
[Unit]
Description=ookla-server
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/ookla/server/
ExecStart=/opt/ookla/server/OoklaServer
KillMode=process
Restart=on-failure
RestartSec=15min

[Install]
WantedBy=multi-user.target
***EOF***
ln -s /opt/ookla/server/ookla-server.service /etc/systemd/system/ookla-server.service
systemctl daemon-reload

# Thats all I wrote
feedback title "Build script finished - https://${instance_id}.${hosting_domain}/wiki/"
