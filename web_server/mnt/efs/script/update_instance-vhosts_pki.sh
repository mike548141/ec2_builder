#!/usr/bin/env bash

# Find the root directory for the apache HTTPD vhosts
vhost_root=`grep -i '^Include[ \t].*/vhosts-httpd.conf$' /etc/httpd/conf.d/vhost.conf | sed 's|Include[ \t]||; s|/vhosts-httpd.conf.*||;'`

# Delete all the symlinks pointing to the vhosts because we don't know which ones are valid and invalid, new ones will be created
for pki_conf in /etc/letsencrypt/renewal/*.conf
do
  if [ -L ${pki_conf} ]
  then
    echo "Deleting symlink ${pki_conf}"
    rm --force ${pki_conf}
  fi
done

# Link each of the vhosts listed in vhosts-httpd.conf to letsencrypt on this instance. So that all instances can renew all certificates as required
vhost_list=`grep -i '^include ' ${vhost_root}/vhosts-httpd.conf | sed "s|[iI]nclude \"${vhost_root}/||g; s|/conf/httpd.conf\"||g;"`
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
