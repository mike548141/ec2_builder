#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_mariadb_server.sh
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
app_mariadb_server () {
  # Install MariaDB server to host databases as Aurora Serverless resume is too slow (~25s from cold to warm). This section will only be used for standalone installs. Eventually this will either use a dedicated EC2 running MariaDB or AWS RDS Aurora
  feedback h1 'MariaDB (MySQL) server'
  pkgmgr install 'mariadb-server'
  feedback body 'Set it to auto start at boot'
  systemctl enable mariadb.service
  feedback h3 'Start the database server'
  restart_service mariadb.service
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
