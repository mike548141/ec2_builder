#!/usr/bin/env bash
#

writeit () {
	cat <<-***EOF*** >> '/root/trouble'
		
		# Server config
		logging.loggers.app.name = Application
		logging.loggers.app.channel.class = FileChannel
		logging.loggers.app.channel.pattern = %Y-%m-%d %H:%M:%S [%P - %I] [%p] %t
		logging.loggers.app.channel.path = /var/log/ooklaserver
		logging.loggers.app.level = information
	***EOF***
}

writeit

