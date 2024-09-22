#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_ookla_speedtest_server.sh
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
app_ookla_speedtest_server () {
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
	cat <<-***EOF*** >> '/opt/ookla/server/OoklaServer.properties.default'

		# Server config
		logging.loggers.app.name = Application
		logging.loggers.app.channel.class = FileChannel
		logging.loggers.app.channel.pattern = %Y-%m-%d %H:%M:%S [%P - %I] [%p] %t
		logging.loggers.app.channel.path = /var/log/ooklaserver
		logging.loggers.app.level = information
	***EOF***
  # Configure a daemon for systemd
	cat <<-***EOF*** > '/opt/ookla/server/ookla-server.service'
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
