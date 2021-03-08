#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.7.60-20210308
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
#   * Swap from Let's Encrypt to AWS ACM for public certs. Removes the external dependency. Keep the Lets Encrypt code for future use
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

# Install an application package
pkgmgr () {
  # Check that the package manager is not already running
  check_pid_lock ${packmgr}
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
    ### Check each package in the array was installed
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
if [ "${1}" == "go" ]
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
  feedback body "Run '${0} go' to execute the script"
  exit 1
fi

#======================================
# Declare the constants
#--------------------------------------
# Get to know the OS so we can support AL2 and Ubuntu
hostos_id=$(grep '^ID=' '/etc/os-release' | sed 's|"||g; s|^ID=||;')
hostos_ver=$(grep '^VERSION_ID=' '/etc/os-release' | sed 's|"||g; s|^VERSION_ID=||;')
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
feedback body "Instance ${instance_id} is in the ${aws_region} region"

# What does the world around the instance look like
tenancy=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'tenancy'].Value" --output text --region ${aws_region})
resource_environment=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'resource_environment'].Value" --output text --region ${aws_region})
service_group=$(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'service_group'].Value" --output text --region ${aws_region})
# Define the parameter store structure
common_parameters="/${tenancy}/${resource_environment}/common"
app_parameters="/${tenancy}/${resource_environment}/${service_group}"
feedback body "Using AWS parameter store ${app_parameters} in the ${aws_region} region"

#======================================
# Declare the variables
#--------------------------------------
get_public_ip

#======================================
# Lets get into it
#--------------------------------------
# Add access to Extra Packages for Enterprise Linux (EPEL) from the Fedora project
case ${hostos_id} in
amzn)
  feedback h1 'Add access to Extra Packages for Enterprise Linux (EPEL) from the Fedora project'
  manage_ale enable 'epel'
  pkgmgr install 'epel-release'
  ;;
esac

# Update the software stack
feedback h1 'Update the software stack'
pkgmgr update
pkgmgr upgrade
systemctl daemon-reload

case ${packmgr} in
apt)
  # Debian (Ubuntu) tools to automate package installations that are interactive
  feedback h1 'Install package management extensions'
  pkgmgr install 'debconf-utils'
  ;;
esac

#### Check cloud-init for warrning or error messages
#### Need to re-test against sshaudit and rebex
#### Also test TLS HTTP2 HSTS etc
#ERROR: cannot verify cakeit.nz's certificate, issued by ‘CN=Let's Encrypt Authority X3,O=Let's Encrypt,C=US’:
# web2.cakeit.nz (_default_ instance cert) seems to be using cakeit.nz vhost cert. Are vhosts working properly i.e default vs cakeit.nz

# Configure the OpenSSH server
feedback h1 'Harden the OpenSSH daemon'
# New host keys incase they are compromised
feedback h2 'Re-generate the RSA and ED25519 keys'
rm --force /etc/ssh/ssh_host_*
ssh-keygen -t rsa -b 4096 -f '/etc/ssh/ssh_host_rsa_key' -N ""
chown root:root '/etc/ssh/ssh_host_rsa_key'
chmod 0600 '/etc/ssh/ssh_host_rsa_key'
ssh-keygen -t ed25519 -f '/etc/ssh/ssh_host_ed25519_key' -N ""
chown root:root '/etc/ssh/ssh_host_ed25519_key'
chmod 0600 '/etc/ssh/ssh_host_ed25519_key'
feedback h2 'Configuration changes'
# Harden the server: DSA and ECDSA host keys can't be trusted
feedback h3 'Disable any host keys in the main SSHD config'
cp '/etc/ssh/sshd_config' '/etc/ssh/sshd_config.bak'
sed -i 's|^HostKey[ \t]|#HostKey |g' '/etc/ssh/sshd_config'
# Support child configs for SSHD
mkdir --parents '/etc/ssh/sshd_config.d/'
if [ -z "$(grep -i 'Include \/etc\/ssh\/sshd_config\.d\/\*\.conf' '/etc/ssh/sshd_config')" ]
then
  ## Ubuntu has this by default, AL2's version of openssh-server (7.4p1-21.amzn2.0.1) does not support it
  feedback error 'Hardening ineffective. SSHD child config added to /etc/ssh/sshd_config but commented out. Please uncomment and restart the service to complete the hardening of SSHD'
  echo '#Include /etc/ssh/sshd_config.d/*.conf' >> '/etc/ssh/sshd_config'
fi
# Use the cipher tech that we trust, tested against https://www.sshaudit.com/
feedback h3 'Adding the child SSHD configs to harden the server'
cat <<***EOF*** > '/etc/ssh/sshd_config.d/host_key.conf'
# SSHD host keys
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Allowed host key exchange algorithms
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
#HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,rsa-sha2-256,rsa-sha2-512,rsa-sha2-256-cert-v01@openssh.com,rsa-sha2-512-cert-v01@openssh.com
***EOF***
cat <<***EOF*** > '/etc/ssh/sshd_config.d/key_exchange.conf'
# Allowed key exchange algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512,diffie-hellman-group-exchange-sha256
***EOF***
cat <<***EOF*** > '/etc/ssh/sshd_config.d/cipher.conf'
# Allowed encryption algorithms (aka ciphers)
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
***EOF***
cat <<***EOF*** > '/etc/ssh/sshd_config.d/mac.conf'
# Allowed Message Authentication Code (MAC) algorithms
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
***EOF***
cat <<***EOF*** > '/etc/ssh/sshd_config.d/protocol.conf'
# Allowed SSH protocols
Protocol 2
***EOF***
cat <<***EOF*** > '/etc/ssh/sshd_config.d/authentication.conf'
# Authentication related config
PubkeyAuthentication yes
AuthenticationMethods publickey
LoginGraceTime 1m
PermitRootLogin no
StrictModes yes
MaxAuthTries 2
PasswordAuthentication no
PermitEmptyPasswords no
Banner /etc/ssh/sshd_banner
AllowGroups ssh
***EOF***
cat <<***EOF*** > '/etc/ssh/sshd_config.d/session.conf'
# SSH session related config
ClientAliveInterval 300
ClientAliveCountMax 24
MaxSessions 10
PrintLastLog yes
***EOF***
# Create a welcome banner
cat <<***EOF*** > '/etc/ssh/sshd_banner'

************************************************************************************************************************************************
*                                                                                                                                              *
* Use of this system is monitored and logged, unauthorised access is prohibited and is subject to criminal and civil penalties.                *
* By proceeding you consent to interception, auditing, and the interrogation of your devices, traffic and information for evidence of mis-use. *
*                                                                                                                                              *
************************************************************************************************************************************************

***EOF***
feedback h3 'Granting the default EC2 user SSH access'
case ${hostos_id} in
ubuntu)
  usermod -aG 'ssh' 'ubuntu'
  ;;
amzn)
  usermod -aG 'ssh' 'ec2-user'
  ;;
esac
# Harden the server: small Diffie-Hellman are weak, we want 3072 bits or more. A 3072-bit modulus is needed to provide 128 bits of security
feedback h2 'Enforce Diffie-Hellman Group Exchange (DH-GEX) protocol moduli >= 3072'
# I am keeping this code as its alot faster than generating a new moduli, I may use it when testing
#cp '/etc/ssh/moduli' '/etc/ssh/moduli.bak'
#awk '$5 >= 3071' '/etc/ssh/moduli' > '/etc/ssh/moduli.safe'
#mv -f '/etc/ssh/moduli.safe' '/etc/ssh/moduli'
mv -f '/etc/ssh/moduli' '/etc/ssh/moduli.bak'
feedback h3 'Generate the new moduli, this will take ~4.5 mins on a t3a.nano and is memory intensive'
ssh-keygen -M generate -O bits=3072 moduli-3072.candidates
feedback h3 'Screen the new moduli, this will take ~22.5 mins on a t3a.nano and is CPU intensive'
ssh-keygen -M screen -f moduli-3072.candidates moduli
# We are done
feedback h2 'Restart OpenSSH server'
systemctl restart sshd.service
systemctl -l status sshd.service

# Configure sudo on the host to allow members of the group sudo. This is default on Ubuntu
feedback h1 'Configure sudo'
if [ ! $(getent group sudo) ]
then
  feedback body 'Create sudo group'
  groupadd --gid 27 'sudo'
fi
if [ -z "$(grep '^%sudo.*ALL=(ALL:ALL) ALL' '/etc/sudoers')" ]
then
  feedback body 'Give the sudo group permissions'
  echo '# Allow members of group sudo to execute any command' > '/etc/sudoers.d/group-sudo'
  echo '%sudo   ALL=(ALL:ALL) ALL' >> '/etc/sudoers.d/group-sudo'
fi

# Create the local users on the host
## This should really link back to a central user repo and users get created dynamically
feedback h1 'Create the user mike and a home directory'
useradd --create-home -c 'Mike Clements' 'mike'
feedback h3 'Add to ssh and sudo groups for access'
usermod -aG 'ssh' 'mike'
usermod -aG 'sudo' 'mike'
feedback h3 'Add SSH key'
mkdir --parents '/home/mike/.ssh'
chown mike:mike '/home/mike/.ssh'
chmod 0700 '/home/mike/.ssh'
wget --tries=2 -O '/home/mike/.ssh/authorized_keys' 'https://cakeit.nz/identity/mike.clements/mike-ssh.pub'
chmod 0600 '/home/mike/.ssh/authorized_keys'

# Additional AWS EC2 tools
feedback h1 'Install AWS tools'
case ${hostos_id} in
ubuntu)
  pkgmgr install 'ec2-ami-tools'
  ;;
amzn)
  feedback body 'No tools to add'
  ;;
esac

# Install the management agents
feedback h1 'System management agents'
# The AWS SSM agent is installed by default on both AL2 and Ubuntu (as a snap package) AMI's. The following packages are not required yet
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
# rkhunter
case ${packmgr} in
apt)
  # Automate the postfix package install by selecting No configuration. Postfix is pulled in as a dependency of rkhunter
  echo 'postfix	postfix/main_mailer_type	select	No configuration' | debconf-set-selections
  ;;
esac
pkgmgr install 'rkhunter'
# tripwire
case ${packmgr} in
apt)
  # Automate the tripwire package install
  echo 'tripwire	tripwire/use-sitekey	boolean	false' | debconf-set-selections
  echo 'tripwire	tripwire/use-localkey	boolean	false' | debconf-set-selections
  echo 'tripwire	tripwire/installed	note	' | debconf-set-selections
  ;;
esac
pkgmgr install 'tripwire'
# Linux security module
case ${hostos_id} in
ubuntu)
  pkgmgr install 'apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra'
  ;;
amzn)
  pkgmgr install 'policycoreutils policycoreutils-python selinux-policy selinux-policy-targeted'
  ##selinux-activate
  sestatus
  ;;
esac
# Linux system auditing
case ${hostos_id} in
ubuntu)
  pkgmgr install 'auditd audispd-plugins'
  ;;
amzn)
  pkgmgr install 'audit audispd-plugins'
  ;;
esac
# OS Query
feedback h3 'Add the osquery repo and trust the GPG key'
case ${packmgr} in
apt)
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 1484120AC4E9F8A1A577AEEE97A80C63C9D8B80B
  add-apt-repository 'deb [arch=amd64] https://pkg.osquery.io/deb deb main'
  ;;
yum)
  curl -L https://pkg.osquery.io/rpm/GPG | tee '/etc/pki/rpm-gpg/RPM-GPG-KEY-osquery'
  rpm --import '/etc/pki/rpm-gpg/RPM-GPG-KEY-osquery'
  yum-config-manager --add-repo https://pkg.osquery.io/rpm/osquery-s3-rpm.repo
  yum-config-manager --enable osquery-s3-rpm
  ;;
esac
pkgmgr update
pkgmgr install 'osquery'

# Google Authenticator adds MFA capability to PAM - https://aws.amazon.com/blogs/startups/securing-ssh-to-amazon-ec2-linux-hosts/ and https://ubuntu.com/tutorials/configure-ssh-2fa#2-installing-and-configuring-required-packages
feedback h1 'Google Authenticator to support MFA'
case ${packmgr} in
apt)
  pkgmgr install 'libpam-google-authenticator'
  ;;
yum)
  pkgmgr install 'google-authenticator'
  ;;
esac

# General tools
feedback h1 'General tools'
# Network tools
pkgmgr install 'ethtool'
# System monitoring
pkgmgr install 'stacer sysstat iotop'
# Install the MariaDB client for connecting to Aurora Serverless to manage the databases
case ${hostos_id} in
ubuntu)
  pkgmgr install 'mariadb-client'
  ;;
amzn)
  pkgmgr install 'mariadb'
  ;;
esac
# Ookla speedtest client
feedback h2 'Ookla client repo'
case ${packmgr} in
apt)
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 379CE192D401AB61
  echo "deb https://ookla.bintray.com/debian generic main" | tee '/etc/apt/sources.list.d/speedtest.list'
  ;;
yum)
  cd ~
  wget --tries=2 https://bintray.com/ookla/rhel/rpm -O bintray-ookla-rhel.repo
  mv ~/bintray-ookla-rhel.repo '/etc/yum.repos.d/bintray-ookla-rhel.repo'
  ;;
esac
pkgmgr update
pkgmgr install 'speedtest'

# Install AWS EFS helper and mount the EFS volume for vhost data
feedback h1 'AWS EFS helper'
case ${packmgr} in
apt)
  mkdir --parents '/opt/aws'
  cd '/opt/aws'
  git clone https://github.com/aws/efs-utils
  cd '/opt/aws/efs-utils'
  ./build-deb.sh
  pkgmgr install ./build/amazon-efs-utils*deb
  ;;
yum)
  pkgmgr install 'amazon-efs-utils'
  ;;
esac
feedback h3 'Mount the EFS volume for vhost data'
# The AWS EFS volume and mount point used to hold virtual host config, content and logs that is shared between web hosts (aka instances)
efs_mount_point=$(aws ssm get-parameter --name "${app_parameters}/awsefs/mount_point" --query 'Parameter.Value' --output text --region ${aws_region})
efs_volume=$(aws ssm get-parameter --name "${app_parameters}/awsefs/volume" --query 'Parameter.Value' --output text --region ${aws_region})
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
feedback h1 'Import the common variables from EFS'
source "${efs_mount_point}/script/common_variables.sh"

# Create a directory for this instances log files on the EFS volume
### Probably remove this section, should not be used anymore but need to check that
feedback h1 'Create a space for this instances log files on the EFS volume'
mkdir --parents "${vhost_root}/_default_/log/${instance_id}.${hosting_domain}"

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
    useradd --uid ${vhost_dir_uid} --gid ${vhost_dir_gid} --shell '/sbin/nologin' --home-dir "${vhost_root}/${vhost_dir}" --no-create-home --groups vhost_owners,vhost_all "${vhost_dir}"
  fi
done

# Root's config for AWS CLI tools held in ~/.aws, after this is set awscli uses the rights assigned to arn:aws:iam::954095588241:user/ec2.web2.cakeit.nz instead of the instance profile arn:aws:iam::954095588241:instance-profile/ec2-web.cakeit.nz and role arn:aws:iam::954095588241:role/ec2-web.cakeit.nz
feedback h1 'Configure AWS CLI for the root user'
aws configure set region ${aws_region}
aws configure set output $(aws ssm get-parameter --name "${common_parameters}/awscli/cli_output" --query 'Parameter.Value' --output text --region ${aws_region})
# Using variables because awscli will stop working when I set half of the credentials. So I need to retrieve both the variables before setting either of them
aws_access_key_id=$(aws ssm get-parameter --name "${common_parameters}/awscli/access_key_id" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption)
aws_secret_access_key=$(aws ssm get-parameter --name "${common_parameters}/awscli/access_key_secret" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption)
aws configure set aws_access_key_id ${aws_access_key_id}
aws configure set aws_secret_access_key ${aws_secret_access_key}
unset aws_access_key_id
unset aws_secret_access_key

# Install Fuse S3FS and mount the S3 bucket for web server data - https://github.com/s3fs-fuse/s3fs-fuse
feedback h1 'Fuse S3FS'
case ${hostos_id} in
ubuntu)
  pkgmgr install 's3fs'
  ;;
amzn)
  pkgmgr install 's3fs-fuse'
  ;;
esac
feedback h3 'Configure FUSE'
cp '/etc/fuse.conf' '/etc/fuse.conf.bak'
sed -i 's|^# user_allow_other$|user_allow_other|' '/etc/fuse.conf'
feedback h3 'Mount the S3 bucket for static web data'
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
pkgmgr install 'nodejs npm'
# PHP
case ${hostos_id} in
ubuntu)
  pkgmgr install 'php-cli php-fpm php-common php-pdo php-json php-mysqlnd php-bcmath php-gd php-intl php-mbstring php-xml php-pear'
  php_service='php7.4-fpm.service'
  # Create a PHP config for the _default_ vhost
  feedback h3 'Create a PHP-FPM config on EBS for this instances _default_ vhost'
  cp "${vhost_root}/_default_/conf/instance-specific-php-fpm.conf" '/etc/php/7.4/fpm/pool.d/this-instance.conf'
  sed -i "s|i-.*\.cakeit\.nz|${instance_id}.${hosting_domain}|g" '/etc/php/7.4/fpm/pool.d/this-instance.conf'
  # Include the vhost config on the EFS volume
  feedback h3 'Include the vhost config on the EFS volume'
  echo '; Include the vhosts stored on the EFS volume' > '/etc/php/7.4/fpm/pool.d/vhost.conf'
  echo "include=${efs_mount_point}/conf/*.php-fpm.conf" >> '/etc/php/7.4/fpm/pool.d/vhost.conf'
  ;;
amzn)
  manage_ale enable 'php7.3'
  pkgmgr install 'php-cli php-fpm php-common php-pdo php-json php-mysqlnd php-bcmath php-gd php-intl php-mbstring php-xml php-pear php-pecl-apcu php-pecl-imagick php-pecl-libsodium php-pecl-zip'
  php_service='php-fpm.service'
  # Create a PHP config for the _default_ vhost
  feedback h3 'Create a PHP-FPM config on EBS for this instances _default_ vhost'
  cp "${vhost_root}/_default_/conf/instance-specific-php-fpm.conf" '/etc/php-fpm.d/this-instance.conf'
  sed -i "s|i-.*\.cakeit\.nz|${instance_id}.${hosting_domain}|g" '/etc/php-fpm.d/this-instance.conf'
  # Include the vhost config on the EFS volume
  feedback h3 'Include the vhost config on the EFS volume'
  echo '; Include the vhosts stored on the EFS volume' > '/etc/php-fpm.d/vhost.conf'
  echo "include=${efs_mount_point}/conf/*.php-fpm.conf" >> '/etc/php-fpm.d/vhost.conf'
  ;;
esac
# Create folder to php logs for the instance (not the vhosts)
mkdir --parents '/var/log/php'
feedback h3 'Restart PHP-FPM to recognise the additional PHP modules and config'
systemctl restart ${php_service}
systemctl -l status ${php_service}

# Install MariaDB server to host databases as Aurora Serverless resume is too slow (~25s from cold to warm). This section will only be used for standalone installs. Eventually this will either use a dedicated EC2 running MariaDB or AWS RDS Aurora
feedback h1 'MariaDB (MySQL) server'
pkgmgr install 'mariadb-server'
feedback body 'Set it to auto start at boot'
systemctl enable mariadb.service
feedback h3 'Start the database server'
systemctl restart mariadb.service

# Install the web server
feedback h1 'Install the web server'
case ${hostos_id} in
ubuntu)
  pkgmgr install 'apache2 apache2-doc apache2-suexec-pristine'
  httpd_service='apache2.service'
  a2disconf apache2-doc
  a2enmod headers
  a2enmod http2
  a2enmod rewrite
  a2enmod ssl
  # Setup the httpd conf for the default vhost specific to this vhosts name
  feedback h3 'Create a _default_ virtual host config on this instance'
  cp "${vhost_root}/_default_/conf/instance-specific-httpd.conf" '/etc/apache2/sites-available/this-instance.conf'
  sed -i "s|i-instanceid\.cakeit\.nz|${instance_id}.${hosting_domain}|g" '/etc/apache2/sites-available/this-instance.conf'
  a2ensite this-instance
  # Include all the vhosts that are enabled on the EFS volume mounted
  feedback h3 'Include the vhost config on the EFS volume'
  ln -s "${efs_mount_point}/conf/vhost-httpd.conf" '/etc/apache2/sites-available/vhost.conf'
  a2ensite vhost
  ;;
amzn)
  manage_ale enable 'httpd_modules'
  pkgmgr install 'httpd mod_ssl'
  httpd_service='httpd.service'
  # Replace the Apache HTTPD MPM module prefork with the module event for HTTP/2 compatibility and to improve server performance
  feedback h3 'Change MPM modules from prefork to event'
  cp '/etc/httpd/conf.modules.d/00-mpm.conf' '/etc/httpd/conf.modules.d/00-mpm.conf.bak'
  sed -i 's|^LoadModule mpm_prefork_module modules/mod_mpm_prefork\.so$|#LoadModule mpm_prefork_module modules/mod_mpm_prefork.so|' '/etc/httpd/conf.modules.d/00-mpm.conf'
  sed -i 's|^#LoadModule mpm_event_module modules/mod_mpm_event\.so$|LoadModule mpm_event_module modules/mod_mpm_event.so|' '/etc/httpd/conf.modules.d/00-mpm.conf'
  # Disable the _default_ SSL config as it will be in the server specific config
  feedback h3 'Disable the default SSL config'
  mv '/etc/httpd/conf.d/ssl.conf' '/etc/httpd/conf.d/ssl.conf.disable'
  # Disable the welcome page config
  feedback h3 'Disable the welcome page config'
  mv '/etc/httpd/conf.d/welcome.conf' '/etc/httpd/conf.d/welcome.conf.disable'
  # Create a config for the server on the EBS volume
  feedback h3 'Create a _default_ virtual host config on this instance'
  cp "${vhost_root}/_default_/conf/instance-specific-httpd.conf" '/etc/httpd/conf.d/this-instance.conf'
  sed -i "s|i-instanceid\.cakeit\.nz|${instance_id}.${hosting_domain}|g" '/etc/httpd/conf.d/this-instance.conf'
  feedback h3 'Include the vhost config on the EFS volume'
  ln -s "${efs_mount_point}/conf/httpd-vhost.conf" '/etc/httpd/conf.d/vhost.conf'
  ;;
esac
feedback body 'Set the web server to auto start at boot'
systemctl enable ${httpd_service}
# The vhosts httpd config points to this conf file, it won't exist yet since LetsEncrypt has not run yet. This creates an empty file so that httpd can load.
if [ ! -f '/etc/letsencrypt/options-ssl-apache.conf' ]
then
  feedback h3 'Create an empty options-ssl-apache.conf because the vhost configs reference it'
  mkdir '/etc/letsencrypt'
  touch '/etc/letsencrypt/options-ssl-apache.conf'
fi
feedback h2 'Extra web hosting software'
case ${packmgr} in
apt)
  cd ~
  wget --tries=2 'https://dl-ssl.google.com/dl/linux/direct/mod-pagespeed-stable_current_amd64.deb'
  chown _apt:root './mod-pagespeed-stable_current_amd64.deb'
  pkgmgr install './mod-pagespeed-stable_current_amd64.deb'
  rm './mod-pagespeed-stable_current_amd64.deb'
  ;;
yum)
  pkgmgr install 'https://dl-ssl.google.com/dl/linux/direct/mod-pagespeed-stable_current_x86_64.rpm'
  ;;
esac
# Install Ghost Script, a PostScript interpreter and renderer that is used by WordPress for PDFs
pkgmgr install 'ghostscript'
feedback h3 'Start the web server'
systemctl restart ${httpd_service}
feedback h3 'Web server status'
systemctl -l status ${httpd_service}

# Get the AWS Elastic IP address used to web host
eip_allocation_id=$(aws ssm get-parameter --name "${app_parameters}/eip_allocation_id" --query 'Parameter.Value' --output text --region ${aws_region})
# If the variable is blank then don't assign an EIP, assume there is a load balancer instead
if [ -z "${eip_allocation_id}" ]
then
  feedback h1 'EIP variable is blank, I assume the IP address for web2.cakeit.nz is bound to a load balancer'
else
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
pkgmgr install 'certbot'
case ${hostos_id} in
ubuntu)
  pkgmgr install 'python3-certbot-apache python-certbot-doc'
  ;;
amzn)
  pkgmgr install 'python2-certbot-apache'
  ;;
esac
# Create and install this instances certificates, these will be kept locally on EBS.  All vhost certificates need to be kept on EFS.
feedback h2 'Get Lets Encrypt certificates for this server'
# The contact email address for Lets Encrypt if a certificate problem comes up
pki_email=$(aws ssm get-parameter --name "${app_parameters}/pki/email" --query 'Parameter.Value' --output text --region ${aws_region})
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
  systemctl restart ${httpd_service}
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
chmod 0770 '/etc/cron.daily/certbot'
case ${hostos_id} in
ubuntu)
  systemctl restart cron.service
  ;;
amzn)
  systemctl restart crond.service
  ;;
esac

# Install Ookla Speedtest server
feedback h1 'Ookla speedtest server'
mkdir --parents '/opt/ookla/server'
cd '/opt/ookla/server/'
wget --tries=2 http://install.speedtest.net/ooklaserver/stable/OoklaServer.tgz
tar -xzvf OoklaServer.tgz OoklaServer-linux64.tar
rm --force OoklaServer.tgz
tar -xzvf OoklaServer-linux64.tar
rm --force OoklaServer-linux64.tar
chown root:root /opt/ookla/server/*
# Customise the config
cp '/opt/ookla/server/OoklaServer.properties.default' '/opt/ookla/server/OoklaServer.properties.default.bak'
sed -i 's|^logging\.loggers\.app\.|#logging.loggers.app.|g' '/opt/ookla/server/OoklaServer.properties.default'
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
ln -s '/opt/ookla/server/ookla-server.service' '/etc/systemd/system/ookla-server.service'
systemctl daemon-reload

# Grab warnings and errors to review
grep -i 'error' '/var/log/cloud-init-output.log' | sort | uniq >> ~/for_review.log
grep -i 'warn' '/var/log/cloud-init-output.log' | sort | uniq >> ~/for_review.log

# Thats all I wrote
feedback title "Build script finished - https://${instance_id}.${hosting_domain}/wiki/"
### add a reboot
exit 0
