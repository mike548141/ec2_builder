#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         create_pki_certificate.sh
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
create_pki_certificate () {
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
  pki_email=$(aws_info ssm "${app_parameters}/pki/email")
  mkdir --parents '/var/log/letsencrypt'
  certbot certonly --domains "${instance_id}.${hosting_domain},web2.${hosting_domain}" --apache --non-interactive --agree-tos --email "${pki_email}" --no-eff-email --logs-dir '/var/log/letsencrypt' --redirect --must-staple --staple-ocsp --hsts --uir

  # Customise the _default_ vhost config to include the new certificate created by certbot
  if [ -f "/etc/letsencrypt/live/${instance_id}.${hosting_domain}/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/${instance_id}.${hosting_domain}/privkey.pem" ]
  then
    feedback h3 'Add the certificates to the web server config'
    sed -i "s|[^#]SSLCertificateFile| #SSLCertificateFile|g; \
            s|[^#]SSLCertificateKeyFile| #SSLCertificateKeyFile|g; \
            s|#SSLCertificateFile[ \t]*/etc/letsencrypt/live/|SSLCertificateFile\t\t/etc/letsencrypt/live/|; \
            s|#SSLCertificateKeyFile[ \t]*/etc/letsencrypt/live/|SSLCertificateKeyFile\t\t/etc/letsencrypt/live/|;" "${httpd_conf}/999-this-instance.conf"
    feedback h3 'Restart the web server'
    restart_service ${httpd_service}
  else
    feedback error 'Failed to create the instances certificates, the web server will use the default (outdated) ones on EFS'
  fi
  # Link each of the vhosts listed in vhosts-httpd.conf to letsencrypt on this instance. So that all instances can renew all certificates as required
  feedback h3 'Setup the vhosts PKI configs on this instance'
  ${efs_mount_point}/script/update_instance-vhosts_pki.sh
  # Run Lets Encrypt Certbot to revoke and/or renew certiicates
  feedback h3 'Renew all certificates'
  certbot renew --no-self-upgrade
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
