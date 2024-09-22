#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_php.sh
# License:      GNU GPL v3
# Language:     bash
# Source:       https://github.com/mike548141/ec2_builder
#
# Description:
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
app_php () {
  case ${hostos_id} in
  ubuntu)
    pkgmgr install 'php php-common php-cli php-fpm php-intl php-pear php-bcmath php-mbstring php-gd php-json php-xml php-mysql php-apcu'
    php_service='php7.4-fpm.service'
    php_conf='/etc/php/7.4/fpm/pool.d'
    mv "${php_conf}/www.conf" "${php_conf}/www.conf.disable"
    ;;
  amzn)
    manage_ale enable 'php7.3'
    pkgmgr install 'php php-common php-cli php-fpm php-intl php-pear php-bcmath php-mbstring php-gd php-json php-xml php-mysqlnd php-pecl-apcu php-pdo php-pecl-imagick php-pecl-libsodium php-pecl-zip'
    php_service='php-fpm.service'
    php_conf='/etc/php-fpm.d'
    ;;
  esac
  # Create a PHP config for the _default_ vhost
  feedback h3 'Create a PHP-FPM config on EBS for this instances _default_ vhost'
  cp "${vhost_root}/_default_/conf/instance-specific-php-fpm.conf" "${php_conf}/999-this-instance.conf"
  sed -i "s|i-.*\.cakeit\.nz|${instance_id}.${hosting_domain}|g" "${php_conf}/999-this-instance.conf"
  # Include the vhost config on the EFS volume
  feedback h3 'Include the vhost config on the EFS volume'
	cat <<-***EOF*** > "${php_conf}/100-vhost.conf"
		; Include the vhosts stored on the EFS volume
		include=${efs_mount_point}/conf/*.php-fpm.conf
	***EOF***
  # Create folder to php logs for the instance (not the vhosts)
  mkdir --parents '/var/log/php'
  feedback h3 'Restart PHP-FPM to recognise the additional PHP modules and config'
  restart_service ${php_service}
  feedback h3 'Restart Apache HTTPD to enable PHP'
  a2enconf php7.4-fpm
  restart_service ${httpd_service}
}

#======================================
# Say hello
#--------------------------------------

#======================================
# Declare the constants
#--------------------------------------

#======================================
# Declare the variables
#--------------------------------------

#======================================
# Lets get into it
#--------------------------------------
