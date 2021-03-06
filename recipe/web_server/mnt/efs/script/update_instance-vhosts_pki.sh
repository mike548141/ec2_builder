#!/usr/bin/env bash

# Import the default variables from the common source
source /mnt/efs/script/common_variables.sh

# Delete all the symlinks pointing to the vhosts because we don't know which ones are valid and invalid, new ones will be created
for pki_conf in /etc/letsencrypt/renewal/*.conf
do
  if [ -L ${pki_conf} ]
  then
    echo "Deleting symlink ${pki_conf}"
    rm --force ${pki_conf}
  fi
done

# Link each of the vhosts listed in vhosts-httpd.conf to the Lets Encrypt config on this instance. So that all instances can renew all certificates as required
for vhost in ${vhost_list}
do
  if [ -f "${vhost_root}/${vhost}/conf/pki.conf" ]
  then
    echo "Creating symlink /etc/letsencrypt/renewal/${vhost}.conf"
    ln -s "${vhost_root}/${vhost}/conf/pki.conf" "/etc/letsencrypt/renewal/${vhost}.conf"
  else
    echo "Error: PKI config file missing for vhost ${vhost}"
  fi
done
