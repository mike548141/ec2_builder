#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_apache2.sh
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
app_apache2 () {
  # Install the web server
  feedback h1 'Install the web server'
  case ${hostos_id} in
  ubuntu)
    pkgmgr install 'apache2 apache2-doc libapache2-mod-fcgid apache2-suexec-pristine'
    httpd_service='apache2.service'
    httpd_conf='/etc/apache2/sites-available'
    feedback h3 'Apache config'
    # Unwanted Apache defaults
    a2disconf apache2-doc charset localized-error-pages other-vhosts-access-log security
    a2dissite 000-default
    # Apache extension we need at the base
    a2enmod headers http2 rewrite ssl
    # PHP-FPM
    a2enmod actions alias proxy_fcgi setenvif
    # Setup the httpd conf for the default vhost specific to this vhosts name
    feedback h3 'Create a _default_ virtual host config on this instance'
    cp "${vhost_root}/_default_/conf/instance-specific-httpd.conf" "${httpd_conf}/999-this-instance.conf"
    sed -i "s|i-instanceid\.cakeit\.nz|${instance_id}.${hosting_domain}|g" "${httpd_conf}/999-this-instance.conf"
    a2ensite 999-this-instance
    # Include all the vhosts that are enabled on the EFS volume mounted
    feedback h3 'Include the vhost config on the EFS volume'
    ln -s "${efs_mount_point}/conf/vhost-httpd.conf" "${httpd_conf}/100-vhost.conf"
    a2ensite 100-vhost
    ;;
  amzn)
    manage_ale enable 'httpd_modules'
    pkgmgr install 'httpd mod_ssl'
    httpd_service='httpd.service'
    httpd_conf='/etc/httpd/conf.d'
    # Replace the Apache HTTPD MPM module prefork with the module event for HTTP/2 compatibility and to improve server performance
    feedback h3 'Change MPM modules from prefork to event'
    cp '/etc/httpd/conf.modules.d/00-mpm.conf' '/etc/httpd/conf.modules.d/00-mpm.conf.bak'
    sed -i 's|^LoadModule mpm_prefork_module modules/mod_mpm_prefork\.so$|#LoadModule mpm_prefork_module modules/mod_mpm_prefork.so|' '/etc/httpd/conf.modules.d/00-mpm.conf'
    sed -i 's|^#LoadModule mpm_event_module modules/mod_mpm_event\.so$|LoadModule mpm_event_module modules/mod_mpm_event.so|' '/etc/httpd/conf.modules.d/00-mpm.conf'
    # Disable the _default_ SSL config as it will be in the server specific config
    feedback h3 'Disable the default SSL config'
    mv "${httpd_conf}/ssl.conf" "${httpd_conf}/ssl.conf.disable"
    # Disable the welcome page config
    feedback h3 'Disable the welcome page config'
    mv "${httpd_conf}/welcome.conf" "${httpd_conf}/welcome.conf.disable"
    # Setup the httpd conf for the default vhost specific to this vhosts name
    feedback h3 'Create a _default_ virtual host config on this instance'
    cp "${vhost_root}/_default_/conf/instance-specific-httpd.conf" "${httpd_conf}/999-this-instance.conf"
    sed -i "s|i-instanceid\.cakeit\.nz|${instance_id}.${hosting_domain}|g" "${httpd_conf}/999-this-instance.conf"
    # Include all the vhosts that are enabled on the EFS volume mounted
    feedback h3 'Include the vhost config on the EFS volume'
    ln -s "${efs_mount_point}/conf/vhost-httpd.conf" "${httpd_conf}/100-vhost.conf"
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
  feedback h3 'Start the web server'
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
