#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.7.4-20191116
# File:         ec2_builder-web_server.sh
# License:      GNU GPL v3
# Language:     bash
#
# Description:
#   Produces a cakeIT web server, developed on an Amazon Linux 2 AMI.
#
# References:
#
# Pre-requisite:
#   The script is dependent upon its IAM role (arn:aws:iam::954095588241:role/ec2-web.cakeit.nz) and the IAM user (arn:aws:iam::954095588241:user/ec2.web2.cakeit.nz) for permissions
#
# Updates:
#
# Improvements to be made:
#   Action: Ensure that when Lets Encrypt renews a vhosts certificate that it stores the latest versions on EFS with the vhost, not on EBS
#   Action: Need a shared user directory for PAM/users. So that file ownership on EFS is the same on all instances
#   Action: Configure a local DB, Aurora Serverless resume is too slow (~25s)
#   Action: Keep all temporal data with vhost e.g. php session and cache data. And configure PHP security features like chroot
#   Action: Import my confluence download and any other info into the wiki
#   Action: Add support to run both PHP 5 and 7
#     - https://stackoverflow.com/questions/42696856/running-two-php-versions-on-the-same-server
#     - https://stackoverflow.com/questions/45033511/how-to-select-php-version-5-and-7-per-virtualhost-in-apache-2-4-on-debian
#   Action: Automate backups of web data (config, DB & files) at the same timestamp to allow easy recovery
#
#   Action: Move websites to web2
#
#   Action: Run the processes that are specific to a vhost as its own user. Q-Username should be domain name or a cn like competitive_edge?
#   Action: Configure security apps for defense in depth, take ideas from my suse studio scripts
#   Action: Add self-testing and self-healing to the build script to make sure everything is built and working properly e.g. did the DNS record create successfully
#
#   Action: SES for mail relay? So don't need SMTP out from server
#   Action: Install Tomcat?
#   Action: Static web data on S3, use a shared bucket to keep admin easy. Ideal would be a bucket per customer for security.
#
#   Action: Upgrade to load balancing the web serving work across 2 or more instances
#   Action: Upgrade to multi-AZ, or even multi-region for all components.
#   Action: Move to a multi-account structure using AWS Organisations. Use AWS CloudFormer to define all the resources in a template.
#   Action: Is there a way to make the AWS AMI (Amazon Linux 2) as read only base, and all writes from this script, users logging in, or system use (e.g. logging) are written to a 2nd EBS volume?
#
#   Action: Get all S3 data into right storage tier. Files smaller than ?128KB? on S3IA or S3. Data larger than that in Deep Archive. Check inventory files.
#
#   Question: Can I shrink the EBS volume, its 8 GB but using 2.3GB
#   Question: Launch instance has a mount EFS volume option, is this better than what I have scripted? Can't find option in launch template
#
# useradd competitive_edge --home-dir /mnt/efs/vhost/cakeit.nz
# chown -R competitive_edge:apache /mnt/efs/vhost/cakeit.nz
#

#======================================
# Declare the arrays
#--------------------------------------

#======================================
# Declare the libraries and functions
#--------------------------------------
check_pid_lock () {
  sleep_count=0
  if [[ ${2} -ge 0 && ${2} -le 3600 ]]
  then
    max_timer=${2}
  else
    max_timer=90
  fi
  while [ -f "/var/run/${1}.pid" ]
  do
    if [[ ${sleep_count} -ge ${max_timer} ]]
    then
      feedback h3 "Giving up waiting for ${1} to exit after ${max_timer} seconds"
      break
    fi
    if [ `ps aux | grep -v grep | grep ${1} | wc -l` -ge 1 ]
    then
      echo "...Waiting 2 seconds for ${1} to exit"
      sleep 2
      sleep_count=$(( ${sleep_count} + 2 ))
    else
      feedback h3 "Deleting the PID file for ${1} because the process is not running"
      sleep 2
      rm "/var/run/${1}.pid"
    fi
  done
}

feedback () {
  if [ "${1}" == "title" ]
  then
    echo ''
    echo '********************************************************************************'
    echo '*                                                                              *'
    echo "*   ${2}"
    echo '*                                                                              *'
    echo '********************************************************************************'
    echo ''
  elif [ "${1}" == "h1" ]
  then
    echo ''
    echo '================================================================================'
    echo "    ${2}"
    echo '--------------------------------------------------------------------------------'
    echo ''
  elif [ "${1}" == "h2" ]
  then
    echo '================================================================================'
    echo "--> ${2}"
  elif [ "${1}" == "h3" ]
  then
    echo '--------------------------------------------------------------------------------'
    echo "--> ${2}"
  elif [ "${1}" == "body" ]
  then
    echo "    ${2}"
  elif [ "${1}" == "error" ]
  then
    echo ''
    echo '********************************************************************************'
    echo " *** *** Error: ${2}"
    echo ''
  else
    echo ''
    echo "*** Error in the feedback function using the following parameters"
    echo "*** P0: ${0}"
    echo "*** P1: ${1}"
    echo "*** P2: ${2}"
    echo ''
  fi
}

install_pkg () {
  #cat /proc/meminfo      # !! Check if there is enough free memory?
  check_pid_lock 'yum'
  yum install -y ${1}
  exit_code=${?}
  if [ ${exit_code} -ne 0 ]
  then
    feedback error "Exit code ${exit_code} from yum"
  fi
  check_pid_lock 'yum'
}

#======================================
# Declare the constants
#--------------------------------------
script_ver=`grep '^# Version:[ \t]*' ${0} | sed 's|# Version:[ \t]*||'`
feedback title "Build script ${0} version ${script_ver} started"

# Define the keys constants to decide what we are building
tenancy='cakeIT'
resource_environment='prod'
service_group='web.cakeit.nz'
app='ec2_builder-web_server.sh'

# Define the parameter store structure
common_parameters="/${tenancy}/${resource_environment}/common"
app_parameters="/${tenancy}/${resource_environment}/${service_group}/${app}"
# The initial AWS region setting using the instances placement so that we can connect to the AWS SSM parameter store
aws_region=`ec2-metadata --availability-zone | cut -c 12-20`
# Get the instance name
instance_id=`ec2-metadata --instance-id | cut -c 14-`

# Configuration parameters are held in AWS Systems Manager Parameter Store, retrieving these using the AWC CLI. Permissions are granted to do this using a IAM role assigned to the instance
feedback h1 'Collecting info from AWS Systems Manager Parameter Store'
# Delete the AWS credentials file so that the AWS CLI uses the instances profile/role permissions
if [ -f '/root/.aws/credentials' ]
then
  rm -f '/root/.aws/credentials'
fi
# Default config for AWS CLI tools
aws_region=`aws ssm get-parameter --name "${app_parameters}/awscli/aws_region" --query 'Parameter.Value' --output text --region ${aws_region}`
aws_cli_output=`aws ssm get-parameter --name "${app_parameters}/awscli/aws_cli_output" --query 'Parameter.Value' --output text --region ${aws_region}`
# The domain name used by the servers for web hosting, this domain name represents the hosting provider and not its customers vhosts
hosting_domain=`aws ssm get-parameter --name "${app_parameters}/hosting_domain" --query 'Parameter.Value' --output text --region ${aws_region}`
# This AWS API key and secret is attached to the IAM user ec2.web.cakeit.nz
aws_access_key_id=`aws ssm get-parameter --name "${app_parameters}/awscli/aws_access_key_id" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption`
aws_secret_access_key=`aws ssm get-parameter --name "${app_parameters}/awscli/aws_secret_access_key" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption`
# Cloudflare API secret
cloudflare_zoneid=`aws ssm get-parameter --name "${common_parameters}/cloudflare/${hosting_domain}/zone_id" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption`
cloudflare_api_token=`aws ssm get-parameter --name "${common_parameters}/cloudflare/${hosting_domain}/api_token" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption`
# The AWS EFS volume and mount point used to hold virtual host config, content and logs that is shared between web hosts (aka instances)
efs_volume=`aws ssm get-parameter --name "${app_parameters}/efs_volume" --query 'Parameter.Value' --output text --region ${aws_region}`
efs_mount_point=`aws ssm get-parameter --name "${app_parameters}/efs_mount_point" --query 'Parameter.Value' --output text --region ${aws_region}`
vhost_root=`aws ssm get-parameter --name "${app_parameters}/vhost_root" --query 'Parameter.Value' --output text --region ${aws_region}`
# The AWS S3 volume used to hold web content that is shared between web hosts, not currently used but is cheaper than EFS
s3_bucket=`aws ssm get-parameter --name "${app_parameters}/s3_bucket" --query 'Parameter.Value' --output text --region ${aws_region}`
s3_mount_point=`aws ssm get-parameter --name "${app_parameters}/s3_mount_point" --query 'Parameter.Value' --output text --region ${aws_region}`
# The contact email address for Lets Encrypt if a certificate problem comes up
pki_email=`aws ssm get-parameter --name "${app_parameters}/pki_email" --query 'Parameter.Value' --output text --region ${aws_region}`
# The AWS Elastic IP address used to web host
eip_allocation_id=`aws ssm get-parameter --name "${app_parameters}/eip_allocation_id" --query 'Parameter.Value' --output text --region ${aws_region}`

#======================================
# Set the initial values for the variables
#--------------------------------------
# Gather instance specific information
public_ipv4=`ec2-metadata --public-ipv4 | cut -c 14-`

#======================================
# Lets get into it
#--------------------------------------
# Allocate the EIP to this instance
feedback h1 'Allocate the EIP public IP address to this instance'
aws ec2 associate-address --instance-id ${instance_id} --allocation-id ${eip_allocation_id} --region ${aws_region}
# Disabled as its still showing the old IP address at this stage, not sure how long until ec2-metadata updates after the EIP is associated. Command now occurs just before Cloudflare is called
#public_ipv4=`ec2-metadata --public-ipv4 | cut -c 14-`

# Update the software stack
feedback h1 'Update the software stack'
yum update -y

# Install the management agents
feedback h1 'Install the management agents'
feedback body 'AWS Systems Manager is installed by default, nothing left to do'
#amazon-linux-extras install -y ansible2 rust1
#install_pkg 'chef puppet'

# Add access to Extra Packages for Enterprise Linux (EPEL) from the Fedora project
feedback h1 'Add access to Extra Packages for Enterprise Linux (EPEL) from the Fedora project'
amazon-linux-extras install -y epel

# Install security apps, requires EPEL
feedback h1 'Install host security apps'
#install_pkg 'fail2ban firewalld rkhunter selinux-policy tripwire'
install_pkg 'rkhunter tripwire'

# Install AWS EFS helper and mount the EFS volume for vhost data
feedback h1 'Install AWS EFS helper'
install_pkg 'amazon-efs-utils'
feedback h2 'Mount the EFS volume for vhost data'
mkdir --parents ${efs_mount_point}
mount -t efs -o tls ${efs_volume}:/ ${efs_mount_point}
feedback h3 'Set it to auto mount at boot'
echo "# Mount AWS EFS volume ${efs_volume} for the web root data">> /etc/fstab
echo "${efs_volume}:/ ${efs_mount_point} efs tls,_netdev 0 0">> /etc/fstab
# Create a directory for this instances log files on the EFS volume
feedback h2 'Create a space for this instances log files on the EFS volume'
mkdir --parents "${vhost_root}/_default_/log/${instance_id}.${hosting_domain}"

# Install Fuse S3FS and mount the S3 bucket for web server data - https://github.com/s3fs-fuse/s3fs-fuse
feedback h1 'Install Fuse S3FS'
install_pkg 's3fs-fuse'
feedback h3 'Configure FUSE'
sed -i 's|^# user_allow_other$|user_allow_other|' /etc/fuse.conf
feedback h3 'Configure AWS CLI for root user, S3FS uses the same credential file'
aws configure set aws_access_key_id ${aws_access_key_id}
aws configure set aws_secret_access_key ${aws_secret_access_key}
aws configure set region ${aws_region}
aws configure set output ${aws_cli_output}
feedback h2 'Mount the S3 bucket for static web data'
mkdir --parents ${s3_mount_point}
s3fs ${s3_bucket} ${s3_mount_point} -o allow_other -o use_path_request_style
feedback h3 'Set it to auto mount at boot'
echo "# Mount AWS S3 bucket ${s3_bucket} for static web data">> /etc/fstab
echo "s3fs#${s3_bucket} ${s3_mount_point} fuse _netdev,allow_other,use_path_request_style 0 0">> /etc/fstab

# Install scripting languages
# Go & Ruby
feedback h1 'Install scripting languages'
feedback h2 'Install Go & Ruby'
install_pkg 'golang ruby'
# Python
feedback h2 'Install Python'
install_pkg 'python python3'
# PHP
feedback h2 'Install PHP 7.3 and some additional PHP modules'
amazon-linux-extras install -y php7.3
install_pkg 'php-bcmath php-gd php-intl php-mbstring php-pecl-apcu php-pecl-imagick php-pecl-libsodium php-pecl-zip php-xml'

# Customise the PHP config
# Create a PHP config for the _default_ vhost
feedback h3 'Create a PHP-FPM config for the _default_ vhost specific to this instance and store it on EBS'
cp "${vhost_root}/_default_/conf/instance-specific-php-fpm.conf" /etc/php-fpm.d/this-instance.conf
sed -i "s|i-.*\.cakeit\.nz|${instance_id}.${hosting_domain}|g" /etc/php-fpm.d/this-instance.conf
# Include the vhost config on the EFS volume
feedback h3 'Include the vhost config on the EFS volume'
echo '; Include the vhosts stored on the EFS volume'> /etc/php-fpm.d/vhost.conf
echo "include=${vhost_root}/vhosts-php-fpm.conf">> /etc/php-fpm.d/vhost.conf
feedback h3 'Restart PHP-FPM to recognise the additional PHP modules and config'
systemctl restart php-fpm

# Install Ghost Script, a PostScript interpreter and renderer that is used by WordPress for PDFs
feedback h1 'Install Ghost Script'
install_pkg 'ghostscript'

# Install Git to support content versioning in MediaWiki
feedback h1 'Install Git'
install_pkg 'git'

# Install the MariaDB client for connecting to Aurora Serverless to manage the databases
feedback h1 'Install the MariaDB client'
install_pkg 'mariadb'

# Install MariaDB server to host databases as Aurora Serverless resume is too slow (~25s)
feedback h1 'Install the MariaDB server'
install_pkg 'mariadb-server'
feedback h3 'Sleep for 5 seconds as the database server wont start immediately after install'
sleep 5
feedback h3 'Start the database server and set it to auto start at boot'
systemctl restart mariadb
systemctl enable mariadb

# Install the web server - https://mozilla.github.io/server-side-tls/ssl-config-generator/
feedback h1 'Install the web server'
amazon-linux-extras install -y httpd_modules
install_pkg 'httpd mod_ssl'
feedback h3 'Start the web server and set it to auto start at boot'
systemctl restart httpd
systemctl enable httpd

# Customise the web server config
feedback h2 'Customise the web server config'
# Install extra modules
feedback h3 'Install additional Apache HTTPD modules'
install_pkg 'https://dl-ssl.google.com/dl/linux/direct/mod-pagespeed-stable_current_x86_64.rpm'
# Replace the Apache HTTPD MPM module prefork with the module event for HTTP/2 compatibility and to improve server performance
feedback h3 'Disable the prefork MPM module and enable the event MPM module'
cp '/etc/httpd/conf.modules.d/00-mpm.conf' '/etc/httpd/conf.modules.d/00-mpm.conf.bak'
sed -i 's|^LoadModule mpm_prefork_module modules/mod_mpm_prefork\.so$|#LoadModule mpm_prefork_module modules/mod_mpm_prefork.so|' /etc/httpd/conf.modules.d/00-mpm.conf
sed -i 's|^#LoadModule mpm_event_module modules/mod_mpm_event\.so$|LoadModule mpm_event_module modules/mod_mpm_event.so|' /etc/httpd/conf.modules.d/00-mpm.conf
# Disable the _default_ SSL config as it will be in the server specific config
feedback h3 'Disable the _default_ SSL config'
mv '/etc/httpd/conf.d/ssl.conf' '/etc/httpd/conf.d/ssl.conf.disable'
# Disable the welcome page config
feedback h3 'Disable the welcome page config'
mv '/etc/httpd/conf.d/welcome.conf' '/etc/httpd/conf.d/welcome.conf.disable'
# Create a config for the server on the EBS volume
feedback h3 'Create a _default_ virtual host config specific to this instance and store it on EBS'
cp "${vhost_root}/_default_/conf/instance-specific-httpd.conf" /etc/httpd/conf.d/this-instance.conf
sed -i "s|i-.*\.cakeit\.nz|${instance_id}.${hosting_domain}|g" /etc/httpd/conf.d/this-instance.conf
# Include the vhost config on the EFS volume
feedback h3 'Include the vhost config on the EFS volume'
echo '# Publish the vhosts stored on the EFS volume'> /etc/httpd/conf.d/vhost.conf
echo "Include ${vhost_root}/vhosts-httpd.conf">> /etc/httpd/conf.d/vhost.conf
feedback h3 'Restart the web server'
systemctl restart httpd

# Create a DNS entry for the web host
feedback h1 'Create DNS entry on Cloudflare'
# Update the public IP address before creating the DNS record, ec2-metadata should have recognised the EIP association by now
public_ipv4=`ec2-metadata --public-ipv4 | cut -c 14-`
curl -X POST "https://api.cloudflare.com/client/v4/zones/${cloudflare_zoneid}/dns_records" \
     -H "Authorization: Bearer ${cloudflare_api_token}" \
     -H "Content-Type: application/json" \
     --data '{"type":"A","name":"'"${instance_id}"'","content":"'"${public_ipv4}"'","ttl":1,"priority":10,"proxied":false}'
feedback h3 'Sleeping for 5 seconds to allow that DNS change to replicate'
sleep 5

# Install Let's Encrypt CertBot, requires EPEL
feedback h1 'Install Lets Encrypt CertBot'
install_pkg 'certbot python2-certbot-apache'

# Create and install this instances certificates, these will be kept locally on EBS.  All vhost certificates need to be kept on EFS.
feedback h2 'Get Lets Encrypt certificates for this server'
certbot certonly --domains "${instance_id}.${hosting_domain},web2.${hosting_domain}" --apache --non-interactive --agree-tos --email "${pki_email}" --no-eff-email --logs-dir "${vhost_root}/_default_/log/letsencrypt" --redirect --must-staple --staple-ocsp --hsts --uir
# Customise the config to include the new certificate created by certbot
if [[ -f "/etc/letsencrypt/live/${instance_id}.${hosting_domain}/fullchain.pem" && -f "/etc/letsencrypt/live/${instance_id}.${hosting_domain}/privkey.pem" ]]
then
  feedback h3 'Add the certificates to the web server config'
  sed -i "s|[^#]SSLCertificateFile| #SSLCertificateFile|g" /etc/httpd/conf.d/this-instance.conf
  sed -i "s|[^#]SSLCertificateKeyFile| #SSLCertificateKeyFile|g" /etc/httpd/conf.d/this-instance.conf
  sed -i "s|#SSLCertificateFile[ \t]*/etc/letsencrypt/live/|SSLCertificateFile\t\t/etc/letsencrypt/live/|" /etc/httpd/conf.d/this-instance.conf
  sed -i "s|#SSLCertificateKeyFile[ \t]*/etc/letsencrypt/live/|SSLCertificateKeyFile\t\t/etc/letsencrypt/live/|" /etc/httpd/conf.d/this-instance.conf
  feedback h3 'Restart the web server'
  systemctl restart httpd
fi
# Link each of the vhosts listed in vhosts-httpd.conf to letsencrypt on this instance. So that all instances can renew all certificates as required
feedback h3 'Include the vhosts Lets Encrypt config on this server'
vhost_list=`grep -i '^include ' ${vhost_root}/vhosts-httpd.conf | sed "s|[iI]nclude \"${vhost_root}/||g; s|/conf/httpd.conf\"||g;"`
for vhost in ${vhost_list}
do
  if [ -f "${vhost_root}/${vhost}/conf/pki.conf" ]
  then
    ln -s "${vhost_root}/${vhost}/conf/pki.conf" "/etc/letsencrypt/renewal/${vhost}.conf"
  else
    feedback error "PKI config file missing for vhost ${vhost}"
  fi
done
# Add a job to cron to run certbot regularly for renewals and revocations
feedback h3 'Add a job to cron to run certbot regularly'
echo '#!/usr/bin/env bash'> /etc/cron.daily/certbot
echo '# Run Lets Encrypt Certbot to revoke and/or renew certiicates'>> /etc/cron.daily/certbot
echo 'certbot renew --no-self-upgrade'>> /etc/cron.daily/certbot
chmod 0700 /etc/cron.daily/certbot
systemctl restart crond

# Thats all I wrote
feedback title "Build script finished - https://${instance_id}.${hosting_domain}/wiki/"
