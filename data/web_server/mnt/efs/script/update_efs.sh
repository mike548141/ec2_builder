#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.1-20210319
# File:         update_efs.sh
# License:      GNU GPL v3
# Language:     bash
# Source:       https://github.com/mike548141/ec2_builder
#
# Description:
#  Sets a number of variables that other scripts rely upon.
#
# References:
#
# Pre-requisite:
#
# Updates:
#
# Improvements to be made:
#

# Import the default variables from the common source
source /mnt/efs/script/common_variables.sh

cd ~/builder
git stash
git pull

cp ~/builder/data/web_server/mnt/efs/conf/vhost-httpd.conf '/mnt/efs/conf/vhost-httpd.conf'

rm --recursive --force /mnt/efs/script/*
cp --recursive ~/builder/data/web_server/mnt/efs/script/* '/mnt/efs/script/'
chmod --recursive 0770 /mnt/efs/script/*.sh

cp ~/builder/data/web_server/mnt/efs/vhost/_default_/conf/instance-specific-httpd.conf '/mnt/efs/vhost/_default_/conf/instance-specific-httpd.conf'
cp ~/builder/data/web_server/mnt/efs/vhost/_default_/conf/instance-specific-php-fpm.conf '/mnt/efs/vhost/_default_/conf/instance-specific-php-fpm.conf'

cp ~/builder/data/web_server/mnt/efs/vhost/cakeit.nz/conf/httpd.conf '/mnt/efs/vhost/cakeit.nz/conf/httpd.conf'
cp ~/builder/data/web_server/mnt/efs/vhost/cakeit.nz/conf/php-fpm.conf '/mnt/efs/vhost/cakeit.nz/conf/php-fpm.conf'
cp ~/builder/data/web_server/mnt/efs/vhost/cakeit.nz/conf/pki.conf '/mnt/efs/vhost/cakeit.nz/conf/pki.conf'

cp ~/builder/data/web_server/mnt/efs/vhost/example.com/conf/httpd.conf '/mnt/efs/vhost/example.com/conf/httpd.conf'
cp ~/builder/data/web_server/mnt/efs/vhost/example.com/conf/php-fpm.conf '/mnt/efs/vhost/example.com/conf/php-fpm.conf'
cp ~/builder/data/web_server/mnt/efs/vhost/example.com/conf/pki.conf '/mnt/efs/vhost/example.com/conf/pki.conf'
