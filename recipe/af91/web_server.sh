#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.7.70-20210314
# File:         web_server.sh
# License:      GNU GPL v3
# Language:     bash
# Source:       https://github.com/mike548141/ec2_builder
#
# Description:
#   Produces a cakeIT web server, developed on an Amazon Linux 2 (AL2) AMI using a t3a.nano instance. Extended to be built on Ubuntu as the primary platform with as much backwards compatibility to AL2 as possible.
#
# References:
#
# Pre-requisite:
#   The script is dependent upon its IAM role (arn:aws:iam::954095588241:role/ec2-web.cakeit.nz) and the IAM user (arn:aws:iam::954095588241:user/ec2.web2.cakeit.nz) for permissions
#
# Updates:
#
# Improvements to be made:
# Decision: Use SAML/OpenID Connect/oAuth or similar to authenticate users to PAM, SSH etc. User should be created dynamically at login, with permissions and config.
  # Create the end user accounts, these user accounts are used to login (e.g. using SSH) to manage a vhost and will generally represent a real person.
  # end users is for customers that actually login via services (e.g. web portal/API etc) or shell (SSH/SCP etc)
  # Get the list of end users from the PKI/SSH keys in vhost/pki?
  # Would be even better if end users used OpenID or oAuth so no credenditals are stored here... Better UX as fewer passwords etc.
  # Not sure if I should/need to specify the UID for end users or leave it to fate
  # End users will need to be a member of the vhost's owner group e.g. mike would be a member of cakeit.nz & competitiveedge.nz which are the primary groups of the vhost owners... A user must be able to be a member of many vhosts with one user ID
  # Must be able to add a user to a owners group to give them access and it sticks (not lost when scripts run to build/update instances). Ant remain consistent across all instances
  # Extend script to delete or disable existing users?  Maybe disable all users in vhost_users and then re-enable if directory still exists?
  # Do I even need to disable as no password? Depend on user ID & SSH/PKI token?
  # Do I use PGP instead of PKI to verify end users? e.g. yum install monkeysphere
# Keep all temporal data with vhost e.g. php session and cache data. And configure PHP security features like chroot
# Import my confluence download and any other info into the wiki
# Use EFS backups only for whole system recovery. Automate per site backups of EFS and DB to S3 so that they are accessible to the customer i.e. don't require us to restore for the customer
#
# Run the processes that are specific to a vhost as its own user. Q-Username should be domain name or a cn like competitive_edge?
# Configure security apps for defense in depth, take ideas from my suse studio scripts
# Add self-testing and self-healing to the build script to make sure everything is built and working properly e.g. did the DNS record create successfully
#
# SES for mail relay? So don't need SMTP out from server
# Static web data on a public S3 bucket, customers can place files there and reference them via an s3 URL so that those downloads are not via the EC2 instance.
#
# Upgrade to load balancing the web serving work across 2 or more instances
# Upgrade to multi-AZ, or even multi-region for all components.
# Move to a multi-account structure using AWS Organisations. Use AWS CloudFormer to define all the resources in a template.
# Is there a way to make the AWS AMI (Amazon Linux 2) as read only base, and all writes from this script, users logging in, or system use (e.g. logging) are written to a 2nd EBS volume?
#
# Get all S3 data into right storage tier. Files smaller than ?128KB? on S3IA or S3. Data larger than that in Deep Archive. Check inventory files.
#
# Can I shrink the EBS volume, its 8 GB but using 2.3GB
#
# Need event based host management system to issue commands to instances, don't use cron as wasted CPU cycles, increased risk of faliure, more complex code base etc
#   - Have HTTPD & PHP reload the config after changing a vhost
#   - add/delete users, groups, and group members as required. Ideally users & groups would be on a directory service
# Ideally this would use IAM users to support MFA and a user ID that could tie to other services e.g. a S3 bucket dedicated to a IAM user
# Swap from Let's Encrypt to AWS ACM for public certs. Removes the external dependency. Keep the Lets Encrypt code for future use
#
## Next
# Move all websites to web2.cakeit.nz. Kill web1 on lightsail
# Create Bodycorp website on wordpress. Upload rules, entitlements, code of conduct etc
# --> Code of conduct for the BC https://mail.google.com/mail/u/0/#drafts/KtbxLvgpngQdZhvbwdFvccNRGqLQjxzGmL (see stickie note on MBP)
# Put my cool HTML5 website up on nova.net.nz again, latest version on the NAS?
# I want to show what you can tell about a web visitor (device, past usage like browsing histroy and the person), how you can track their usage and geophysical. Like deviceinfo.me. With no tag it just shows a generic page, with tag (e.g. https://ushare.myspot.nz/share?showme=yes) it shows the end user what I can see. Some of the other pages in my Hack --> Track show better info that deviceinfo.me like which social media logins you are authenticated too https://browserleaks.com/social
# --> Catch Facebook scammer pretending to be graeme dean
# TerraForm code to create all resources including the AWS Organisations. Owner, overwatch, web_prod, backup

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

app_fedora_epel () {
  # Add access to Extra Packages for Enterprise Linux (EPEL) from the Fedora project
  case ${hostos_id} in
  amzn)
    feedback h1 'Add access to Extra Packages for Enterprise Linux (EPEL) from the Fedora project'
    manage_ale enable 'epel'
    pkgmgr install 'epel-release'
    ;;
  esac
}

app_lsa () {
  # Linux system auditing
  case ${hostos_id} in
  ubuntu)
    pkgmgr install 'auditd audispd-plugins'
    ;;
  amzn)
    pkgmgr install 'audit audispd-plugins'
    ;;
  esac
}

app_lsm () {
  # Linux security module
  case ${hostos_id} in
  ubuntu)
    pkgmgr install 'apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra'
    ;;
  amzn)
    pkgmgr install 'policycoreutils policycoreutils-python selinux-policy selinux-policy-targeted'
    ##selinux-activate
    sestatus
    ;;
  esac
}

app_mariadb_client () {
  # Install the MariaDB client for connecting to Aurora Serverless to manage the databases
  case ${hostos_id} in
  ubuntu)
    pkgmgr install 'mariadb-client'
    ;;
  amzn)
    pkgmgr install 'mariadb'
    ;;
  esac
}

app_mariadb_server () {
  # Install MariaDB server to host databases as Aurora Serverless resume is too slow (~25s from cold to warm). This section will only be used for standalone installs. Eventually this will either use a dedicated EC2 running MariaDB or AWS RDS Aurora
  feedback h1 'MariaDB (MySQL) server'
  pkgmgr install 'mariadb-server'
  feedback body 'Set it to auto start at boot'
  systemctl enable mariadb.service
  feedback h3 'Start the database server'
  restart_service mariadb.service
}

app_ookla_speedtest_client () {
  # Ookla speedtest client
  feedback h2 'Ookla client repo'
  case ${packmgr} in
  apt)
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 379CE192D401AB61
		cat <<-***EOF*** > '/etc/apt/sources.list.d/speedtest.list'
			deb https://ookla.bintray.com/debian generic main
		***EOF***
    ;;
  yum)
    cd ~
    wget --tries=2 https://bintray.com/ookla/rhel/rpm -O bintray-ookla-rhel.repo
    mv ~/bintray-ookla-rhel.repo '/etc/yum.repos.d/bintray-ookla-rhel.repo'
    ;;
  esac
  pkgmgr update
  pkgmgr install 'speedtest'
}

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

app_osquery () {
  # OS Query
  feedback h3 'Add the osquery repo and trust the GPG key'
  case ${packmgr} in
  apt)
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 1484120AC4E9F8A1A577AEEE97A80C63C9D8B80B
    add-apt-repository 'deb [arch=amd64] https://pkg.osquery.io/deb deb main'
    ;;
  yum)
    curl -L https://pkg.osquery.io/rpm/GPG | tee '/etc/pki/rpm-gpg/RPM-GPG-KEY-osquery'
    rpm --import '/etc/pki/rpm-gpg/RPM-GPG-KEY-osquery'
    yum-config-manager --add-repo https://pkg.osquery.io/rpm/osquery-s3-rpm.repo
    yum-config-manager --enable osquery-s3-rpm
    ;;
  esac
  pkgmgr update
  pkgmgr install 'osquery'
}

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

app_rkhunter () {
  # rkhunter
  case ${packmgr} in
  apt)
    # Automate the postfix package install by selecting No configuration. Postfix is pulled in as a dependency of rkhunter
    echo 'postfix	postfix/main_mailer_type	select	No configuration' | debconf-set-selections
    ;;
  esac
  pkgmgr install 'rkhunter'
}

app_sshd () {
  # Configure the OpenSSH server
  feedback h1 'Harden the OpenSSH daemon'
  # New host keys incase they are compromised
  feedback h2 'Re-generate the RSA and ED25519 keys'
  rm --force /etc/ssh/ssh_host_*
  ssh-keygen -t rsa -b 4096 -f '/etc/ssh/ssh_host_rsa_key' -N ""
  chown root:root '/etc/ssh/ssh_host_rsa_key'
  chmod 0600 '/etc/ssh/ssh_host_rsa_key'
  ssh-keygen -t ed25519 -f '/etc/ssh/ssh_host_ed25519_key' -N ""
  chown root:root '/etc/ssh/ssh_host_ed25519_key'
  chmod 0600 '/etc/ssh/ssh_host_ed25519_key'
  feedback h2 'Configuration changes'
  # Harden the server: DSA and ECDSA host keys can't be trusted
  feedback h3 'Disable any host keys in the main SSHD config'
  cp '/etc/ssh/sshd_config' '/etc/ssh/sshd_config.bak'
  sed -i 's|^HostKey[ \t]|#HostKey |g' '/etc/ssh/sshd_config'
  # Support child configs for SSHD
  mkdir --parents '/etc/ssh/sshd_config.d/'
  if [ -z "$(grep -i 'Include \/etc\/ssh\/sshd_config\.d\/\*\.conf' '/etc/ssh/sshd_config')" ]
  then
    # Ubuntu has this by default, AL2's version of openssh-server (7.4p1-21.amzn2.0.1) does not support it
    feedback error 'Hardening ineffective. SSHD child config added to /etc/ssh/sshd_config but commented out. Please uncomment and restart the service to complete the hardening of SSHD'
		cat <<-***EOF*** >> '/etc/ssh/sshd_config'
			#Include /etc/ssh/sshd_config.d/*.conf
		***EOF***
  fi
  # Use the cipher tech that we trust, tested against https://www.sshaudit.com/
  feedback h3 'Adding the child SSHD configs to harden the server'
  feedback body 'Host keys'
	cat <<-***EOF*** > '/etc/ssh/sshd_config.d/host_key.conf'
		# SSHD host keys
		HostKey /etc/ssh/ssh_host_ed25519_key
		HostKey /etc/ssh/ssh_host_rsa_key
	***EOF***
  feedback body 'Host key exchange algorithms'
	cat <<-***EOF*** > '/etc/ssh/sshd_config.d/host_key_exchange.conf'
		# Allowed host key exchange algorithms
		HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
		#HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,rsa-sha2-256,rsa-sha2-512,rsa-sha2-256-cert-v01@openssh.com,rsa-sha2-512-cert-v01@openssh.com
	***EOF***
  feedback body 'Key exchange algorithms'
	cat <<-***EOF*** > '/etc/ssh/sshd_config.d/key_exchange.conf'
		# Allowed key exchange algorithms
		KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512,diffie-hellman-group-exchange-sha256
	***EOF***
  feedback body 'Ciphers'
	cat <<-***EOF*** > '/etc/ssh/sshd_config.d/cipher.conf'
		# Allowed encryption algorithms (aka ciphers)
		Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
	***EOF***
  feedback body 'Message Authentication Code (MAC) algorithms'
	cat <<-***EOF*** > '/etc/ssh/sshd_config.d/mac.conf'
		# Allowed Message Authentication Code (MAC) algorithms
		MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
	***EOF***
  feedback body 'SSH protocol'
	cat <<-***EOF*** > '/etc/ssh/sshd_config.d/protocol.conf'
		# Allowed SSH protocols
		Protocol 2
	***EOF***
  feedback body 'SSHD authentication config'
	cat <<-***EOF*** > '/etc/ssh/sshd_config.d/authentication.conf'
		# Authentication related config
		PubkeyAuthentication yes
		AuthenticationMethods publickey
		LoginGraceTime 1m
		PermitRootLogin no
		StrictModes yes
		MaxAuthTries 2
		PasswordAuthentication no
		PermitEmptyPasswords no
		Banner /etc/ssh/sshd_banner
		AllowGroups ssh
	***EOF***
  feedback body 'SSHD session config'
	cat <<-***EOF*** > '/etc/ssh/sshd_config.d/session.conf'
		# SSH session related config
		ClientAliveInterval 15
		ClientAliveCountMax 40
		MaxSessions 10
		PrintLastLog yes
	***EOF***
  # Create a welcome banner
  feedback body 'SSHD welcome banner'
	cat <<-***EOF*** > '/etc/ssh/sshd_banner'

		************************************************************************************************************************************************
		*                                                                                                                                              *
		* Use of this system is monitored and logged, unauthorised access is prohibited and is subject to criminal and civil penalties.                *
		* By proceeding you consent to interception, auditing, and the interrogation of your devices, traffic and information for evidence of mis-use. *
		*                                                                                                                                              *
		************************************************************************************************************************************************

	***EOF***
  feedback h3 'Granting the default EC2 user SSH access'
  case ${hostos_id} in
  ubuntu)
    usermod -aG 'ssh' 'ubuntu'
    ;;
  amzn)
    usermod -aG 'ssh' 'ec2-user'
    ;;
  esac
  # Harden the server: small Diffie-Hellman are weak, we want 3072 bits or more. A 3072-bit modulus is needed to provide 128 bits of security
  feedback h2 'Enforce Diffie-Hellman Group Exchange (DH-GEX) protocol moduli >= 3072 bits'
  ## fast = slow
  if [ 'fast' == 'fast' ]
  then
    # I am keeping this code as its alot faster than generating a new moduli so I may use it when testing
    cp '/etc/ssh/moduli' '/etc/ssh/moduli.bak'
    awk '$5 >= 3071' '/etc/ssh/moduli' > '/etc/ssh/moduli.safe'
    mv -f '/etc/ssh/moduli.safe' '/etc/ssh/moduli'
  else
    mv -f '/etc/ssh/moduli' '/etc/ssh/moduli.bak'
    feedback h3 "Generate the new moduli, this will take ~4.5 mins on a t3a.nano and is memory intensive. Started: $(date)"
    ssh-keygen -M generate -O bits=3072 '/etc/ssh/moduli-3072.candidates'
    feedback h3 "Screen the new moduli, this will take ~22.5 mins on a t3a.nano and is CPU intensive. Started: $(date)"
    ssh-keygen -M screen -f '/etc/ssh/moduli-3072.candidates' '/etc/ssh/moduli'
  fi
  # We are done
  feedback h2 'Restart OpenSSH server'
  restart_service sshd.service
}

app_sudo () {
  # Configure sudo on the host to allow members of the group sudo. This is default on Ubuntu
  feedback h1 'Configure sudo'
  if [ ! $(getent group sudo) ]
  then
    feedback body 'Create sudo group'
    groupadd --gid 27 'sudo'
  fi
  if [ -z "$(grep '^%sudo.*ALL=(ALL:ALL) ALL' '/etc/sudoers')" ]
  then
    feedback body 'Give the sudo group permissions'
		cat <<-***EOF*** > '/etc/sudoers.d/group-sudo'
			# Allow members of group sudo to execute any command
			%sudo   ALL=(ALL:ALL) ALL
		***EOF***
	fi
}

app_terraform () {
  # TerraForm
  curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
  apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
  pkgmgr update
  pkgmgr install terraform
  terraform -install-autocomplete
}

app_tripwire () {
  # tripwire
  case ${packmgr} in
  apt)
    # Automate the tripwire package install
    echo 'tripwire	tripwire/use-sitekey	boolean	false' | debconf-set-selections
    echo 'tripwire	tripwire/use-localkey	boolean	false' | debconf-set-selections
    echo 'tripwire	tripwire/installed	note	' | debconf-set-selections
    ;;
  esac
  pkgmgr install 'tripwire'
}

associate_eip () {
  # Get the AWS Elastic IP address used to web host
  eip_allocation_id=$(aws_info ssm "${app_parameters}/eip_allocation_id")
  # If the variable is blank then don't assign an EIP, assume there is a load balancer instead
  if [ -z "${eip_allocation_id}" ]
  then
    feedback h1 'EIP variable is blank, I assume the IP address for web2.cakeit.nz is bound to a load balancer'
  else
    # Allocate the AWS EIP to this instance
    feedback h1 'Allocate the EIP public IP address to this instance'
    ## Find out what instance is currently holding the EIP if any
    # Allocate the EIP
    aws ec2 associate-address --instance-id ${instance_id} --allocation-id ${eip_allocation_id} --region ${aws_region}
    # Update the public IP address assigned now the EIP is associated
    feedback body 'Sleep for 5 seconds to allow metadata to update after the EIP association'
    sleep 5
    what_is_public_ip
    feedback body "EIP address ${public_ipv4} associated"
  fi
}

aws_info () {
  case ${1} in
  ec2_tag)
    echo $(aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == '${2}'].Value" --output text --region ${aws_region})
    ;;
  ssm)
    echo $(aws ssm get-parameter --name "${2}" --query 'Parameter.Value' --output text --region ${aws_region})
    ;;
  ssm_secure)
    echo $(aws ssm get-parameter --name "${2}" --query 'Parameter.Value' --output text --region ${aws_region} --with-decryption)
    ;;
  *)
    feedback error "Function aws_info does not handle ${1}"
    ;;
  esac
}

check_packages () {
  # Handle a list of multiple packages by looping through them
  for one_pkg in ${2}
  do
    # Lookup the package name if given a file name
    if [ $(echo ${one_pkg} | grep -i '\.deb$') ]
    then
      local one_clean_pkg=$(dpkg --info ${one_pkg} | grep ' Package: ' | sed 's|^ Package: ||;')
    elif [ $(echo ${one_pkg} | grep -i '\.rpm$') ]
    then
      ## Add support for rpm packages
      local one_clean_pkg='oops TBC'
    else
      local one_clean_pkg=${one_pkg}
    fi
    
    # Check if the package is listed in the package manger database
    if [ -z "$(apt list --installed ${one_clean_pkg} | grep -v '^Listing')" ]
    then
      if [ "${1}" == "present" ]
      then
        feedback error "The package ${one_clean_pkg} has not installed properly"
      fi
    else
      if [ "${1}" == "absent" ]
      then
        feedback error "The package ${one_clean_pkg} is already installed"
      fi
    fi
  done
}

# Checks if the app is running, and waits for it to exit cleanly
check_pid_lock () {
  local sleep_timer=0
  local sleep_max_timer=90
  # Input error check for the function variables
  if [[ ${2} =~ [^0-9] ]]
  then
    feedback error "check_pid_lock Invalid timer specified, using default of ${sleep_max_timer}"
  elif [[ -n ${2} && ${2} -ge 0 && ${2} -le 3600 ]]
  then
    sleep_max_timer=${2}
  elif [[ -n ${2} ]]
  then
    feedback error "check_pid_lock Timer outside of 0-3600 range, using default of ${sleep_max_timer}"
  fi
  # Watches to see the process (pid) has terminated
  while [ -f "/var/run/${1}.pid" ]
  do
    if [[ ${sleep_timer} -ge ${sleep_max_timer} ]]
    then
      feedback error "Giving up waiting for ${1} to exit after ${sleep_timer} of ${sleep_max_timer} seconds"
      break
    elif [ $(ps -ef | grep -v 'grep' | grep "${1}" | wc -l) -ge 1 ]
    then
      feedback body "function timer: Waiting for ${1} to exit"
      sleep 1
      sleep_timer=$(( ${sleep_timer} + 1 ))
    else
      ## I should safety check this, make sure I'm not deleting the pid file with the process still running
      feedback error "Deleting the PID file for ${1} because the process is not running"
      rm --force "/var/run/${1}.pid"
      break
    fi
  done
}

configure_awscli () {
  # Root's config for AWS CLI tools held in ~/.aws, after this is set awscli uses the rights assigned to arn:aws:iam::954095588241:user/ec2.web2.cakeit.nz instead of the instance profile arn:aws:iam::954095588241:instance-profile/ec2-web.cakeit.nz and role arn:aws:iam::954095588241:role/ec2-web.cakeit.nz
  feedback h1 'Configure AWS CLI for the root user'
  aws configure set region ${aws_region}
  aws configure set output $(aws_info ssm "${common_parameters}/awscli/cli_output")
  # Using variables because awscli will stop working when I set half of the credentials. So I need to retrieve both the variables before setting either of them
  local aws_access_key_id=$(aws_info ssm_secure "${common_parameters}/awscli/access_key_id")
  local aws_secret_access_key=$(aws_info ssm_secure "${common_parameters}/awscli/access_key_secret")
  aws configure set aws_access_key_id ${aws_access_key_id}
  aws configure set aws_secret_access_key ${aws_secret_access_key}
}

create_dns_record () {
  # Create a DNS entry for the web host
  feedback h1 'Create a DNS entry on Cloudflare for this instance'
  # Cloudflare API secret
  cloudflare_zoneid=$(aws_info ssm_secure "${common_parameters}/cloudflare/${hosting_domain}/zone_id")
  local cloudflare_api_token=$(aws_info ssm_secure "${common_parameters}/cloudflare/${hosting_domain}/api_token")
  curl -X POST "https://api.cloudflare.com/client/v4/zones/${cloudflare_zoneid}/dns_records" \
       -H "Authorization: Bearer ${cloudflare_api_token}" \
       -H "Content-Type: application/json" \
       --data '{"type":"A","name":"'"${instance_id}"'","content":"'"${public_ipv4}"'","ttl":1,"priority":10,"proxied":false}'
  ##curl -X POST "https://api.cloudflare.com/client/v4/zones/${cloudflare_zoneid}/dns_records" \
  ##     -H "Authorization: Bearer ${cloudflare_api_token}" \
  ##     -H "Content-Type: application/json" \
  ##     --data '{"type":"AAAA","name":"'"${instance_id}"'","content":"'"${public_ipv6}"'","ttl":1,"priority":10,"proxied":false}'
  feedback h3 'Sleeping for 5 seconds to allow that DNS change to replicate'
  sleep 5
}

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

disable_service () {
  systemctl disable ${1}
  systemctl stop ${1}
  systemctl -l status ${1}
}

# Beautifies the feedback to std_out
feedback () {
  case ${1} in
  title)
    echo ''
    echo '********************************************************************************'
    echo '*                                                                              *'
    echo "*   ${2}"
    echo '*                                                                              *'
    echo '********************************************************************************'
    echo ''
    ;;
  h1)
    echo ''
    echo '================================================================================'
    echo "    ${2}"
    echo '================================================================================'
    echo ''
    ;;
  h2)
    echo ''
    echo '================================================================================'
    echo "--> ${2}"
    echo '--------------------------------------------------------------------------------'
    ;;
  h3)
    echo '--------------------------------------------------------------------------------'
    echo "--> ${2}"
    ;;
  body)
    echo "--> ${2}"
    ;;
  error)
    echo ''
    echo '********************************************************************************'
    echo " *** Error: ${2}"
    echo ''
    ;;
  *)
    echo ''
    echo "*** Error in the feedback function using the following parameters"
    echo "*** P0: ${0}"
    echo "*** P1: ${1}"
    echo "*** P2: ${2}"
    echo ''
    ;;
  esac
}

mount_efs_volume () {
  # Install AWS EFS helper and mount the EFS volume for vhost data
  feedback h1 'AWS EFS helper'
  case ${packmgr} in
  apt)
    mkdir --parents '/opt/aws'
    cd '/opt/aws'
    git clone https://github.com/aws/efs-utils
    cd '/opt/aws/efs-utils'
    ./build-deb.sh
    pkgmgr install ./build/amazon-efs-utils-*.deb
    ;;
  yum)
    pkgmgr install 'amazon-efs-utils'
    ;;
  esac
  feedback h3 'Mount the EFS volume for vhost data'
  # The AWS EFS volume and mount point used to hold virtual host config, content and logs that is shared between web hosts (aka instances)
  efs_mount_point=$(aws_info ssm "${app_parameters}/awsefs/mount_point")
  efs_volume=$(aws_info ssm "${app_parameters}/awsefs/volume")
  mkdir --parents ${efs_mount_point}
  if mountpoint -q ${efs_mount_point}
  then
    umount ${efs_mount_point}
  fi
  mount -t efs -o tls ${efs_volume}:/ ${efs_mount_point}
  feedback body 'Set it to auto mount at boot'
	cat <<-***EOF*** >> '/etc/fstab'
		# Mount AWS EFS volume ${efs_volume} for the web root data
		${efs_volume}:/ ${efs_mount_point} efs tls,_netdev 0 0
	***EOF***
}

mount_s3_bucket () {
  # Install Fuse S3FS and mount the S3 bucket for web server data - https://github.com/s3fs-fuse/s3fs-fuse
  feedback h1 'Fuse S3FS'
  ## The S3 function should run configure_awscli since its dependent upon it
  case ${hostos_id} in
  ubuntu)
    pkgmgr install 's3fs'
    ;;
  amzn)
    pkgmgr install 's3fs-fuse'
    ;;
  esac
  feedback h3 'Configure FUSE'
  cp '/etc/fuse.conf' '/etc/fuse.conf.bak'
  sed -i 's|^# user_allow_other$|user_allow_other|' '/etc/fuse.conf'
  feedback h3 'Mount the S3 bucket for static web data'
  mkdir --parents ${s3_mount_point}
  if mountpoint -q ${s3_mount_point}
  then
    umount ${s3_mount_point}
  fi
  s3fs ${s3_bucket} ${s3_mount_point} -o allow_other -o use_path_request_style
  feedback body 'Set it to auto mount at boot'
	cat <<-***EOF*** >> '/etc/fstab'
		# Mount AWS S3 bucket ${s3_bucket} for static web data
		s3fs#${s3_bucket} ${s3_mount_point} fuse _netdev,allow_other,use_path_request_style 0 0
	***EOF***
}

pam_google_mfa () {
  # Google Authenticator adds MFA capability to PAM - https://aws.amazon.com/blogs/startups/securing-ssh-to-amazon-ec2-linux-hosts/ and https://ubuntu.com/tutorials/configure-ssh-2fa#2-installing-and-configuring-required-packages
  feedback h1 'Google Authenticator to support MFA'
  case ${packmgr} in
  apt)
    pkgmgr install 'libpam-google-authenticator'
    ;;
  yum)
    pkgmgr install 'google-authenticator'
    ;;
  esac
  ## Add the configuration to use this with SSH
}

# Install an application package
pkgmgr () {
  # Check that the package manager is not already running
  check_pid_lock ${packmgr}
  case ${1} in
  update)
    feedback h3 'Get updates from package repositories'
    case ${packmgr} in
    apt)
      apt-get --assume-yes update
      local exit_code=${?}
      ;;
    yum)
      yum --assumeyes update
      local exit_code=${?}
      ;;
    esac
    ;;
  upgrade)
    feedback h3 'Upgrade installed packages'
    case ${packmgr} in
    apt)
      apt-get --assume-yes upgrade
      local exit_code=${?}
      ;;
    yum)
      yum --assumeyes upgrade
      local exit_code=${?}
      ;;
    esac
    ;;
  install)
    # Check if any of the packages are already installed
    check_packages absent "${2}"
    feedback h3 "Install ${2}"
    case ${packmgr} in
    apt)
      apt-get --assume-yes install ${2}
      local exit_code=${?}
      ;;
    yum)
      yum --assumeyes install ${2}
      local exit_code=${?}
      ;;
    esac
    # Check that each of the packages are now showing as installed in the package database to verify it completed properly
    check_packages present "${2}"
    ;;
  *)
    feedback error "The package manager function can not understand the command ${1}"
    ;;
  esac
  if [ ${exit_code} -ne 0 ]
  then
    feedback error "${packmgr} exit code ${exit_code}"
  else
    feedback body "Thumbs up, ${packmgr} exit code ${exit_code}"
  fi
  # Wait for the package manager to terminate
  check_pid_lock ${packmgr}
}

# Wrap the amazon_linux_extras script with additional steps
manage_ale () {
  case ${hostos_id} in
  amzn)
    amazon-linux-extras ${1} ${2}
    yum clean metadata
    ;;
  esac
}

restart_service () {
  systemctl restart ${1}
  systemctl -l status ${1}
}

what_is_instance_meta () {
  # AWS region and EC2 instance ID so we can use awscli
  if [ -f '/usr/bin/ec2metadata' ]
  then
    aws_region=$(ec2metadata --availability-zone | cut -c 1-9)
    instance_id=$(ec2metadata --instance-id)
  elif [ -f '/usr/bin/ec2-metadata' ]
  then
    aws_region=$(ec2-metadata --availability-zone | cut -c 12-20)
    instance_id=$(ec2-metadata --instance-id | cut -c 14-)
  else
    feedback error "Can't find ec2metadata or ec2-metadata"
  fi
  if [ -z "${aws_region}" ]
  then
    aws_region='us-east-1'
    feedback error "AWS region not set, assuming ${aws_region}"
  fi
}

what_is_package_manager () {
  # Which package manger do we have to work with
  if [ -f '/usr/bin/apt' ]
  then
    packmgr='apt'
  elif [ -f '/usr/bin/yum' ]
  then
    packmgr='yum'
  else
    feedback error 'Package manager not found'
  fi
}

# Find what Public IP addresses are assigned to the instance
what_is_public_ip () {
  if [ -f '/usr/bin/ec2metadata' ]
  then
    public_ipv4=$(ec2metadata --public-ipv4)
    ##public_ipv6=$(ec2metadata --public-ipv6 | cut -c 14-)
  elif [ -f '/usr/bin/ec2-metadata' ]
  then
    public_ipv4=$(ec2-metadata --public-ipv4 | cut -c 14-)
    ##public_ipv6=$(ec2-metadata --public-ipv6 | cut -c 14-)
  else
    feedback error "Can't find ec2metadata or ec2-metadata to find the public IP"
  fi
}

#======================================
# Say hello
#--------------------------------------
if [ "${1}" == "launch" ]
then
  feedback title 'ec2_builder build script'
  script_ver=$(grep '^# Version:[ \t]*' ${0} | sed 's|# Version:[ \t]*||')
  hostos_pretty=$(grep '^PRETTY_NAME=' '/etc/os-release' | sed 's|"||g; s|^PRETTY_NAME=||;')
  feedback body "Script: ${0}"
  feedback body "Script version: ${script_ver}"
  feedback body "OS: ${hostos_pretty}"
  feedback body "User: $(whoami)"
  feedback body "Shell: $(readlink /proc/$$/exe)"
  feedback body "Started: $(date)"
else
  feedback error 'Exiting because you did not use the special word'
  feedback body 'This is to protect against running this script unintentionally, it could cause damage to the host'
  feedback body "Run '${0} launch' to execute the script"
  exit 1
fi

#======================================
# Declare the constants
#--------------------------------------
# Get to know the OS so we can support AL2 and Ubuntu
hostos_id=$(grep '^ID=' '/etc/os-release' | sed 's|"||g; s|^ID=||;')
hostos_ver=$(grep '^VERSION_ID=' '/etc/os-release' | sed 's|"||g; s|^VERSION_ID=||;')

what_is_package_manager

what_is_instance_meta

#======================================
# Declare the variables
#--------------------------------------
tenancy=$(aws_info ec2_tag 'tenancy')
resource_environment=$(aws_info ec2_tag 'resource_environment')
service_group=$(aws_info ec2_tag 'service_group')
# Define the parameter store structure based on the meta we just grabbed
common_parameters="/${tenancy}/${resource_environment}/common"
app_parameters="/${tenancy}/${resource_environment}/${service_group}"

what_is_public_ip

#======================================
# Lets get into it
#--------------------------------------
feedback body "Instance ${instance_id} is using AWS parameter store ${app_parameters} in the ${aws_region} region"

app_fedora_epel

# Update the software stack
feedback h1 'Update the software stack'
pkgmgr update
pkgmgr upgrade
systemctl daemon-reload

case ${packmgr} in
apt)
  # Debian (Ubuntu) tools to automate package installations that are interactive
  feedback h1 'Install package management extensions'
  pkgmgr install 'debconf-utils'
  ;;
esac

# Configure and secure the SSH daemon
app_sshd

app_sudo

# Create the local users on the host
## This should really link back to a central user repo and users get created dynamically when they login e.g. Google SAML IDP
feedback h1 'Create the user mike'
useradd --shell '/bin/bash' --create-home -c 'Mike Clements' --groups ssh,sudo 'mike'
feedback h3 'Add SSH key'
mkdir --parents '/home/mike/.ssh'
chown mike:mike '/home/mike/.ssh'
chmod 0700 '/home/mike/.ssh'
wget --tries=2 -O '/home/mike/.ssh/authorized_keys' 'https://cakeit.nz/identity/mike.clements/mike-ssh.pub'
chmod 0600 '/home/mike/.ssh/authorized_keys'
#### Received disconnect from 3.209.113.180 port 22:2: Too many authentication failures - PKI auth isn't working

feedback h1 'Systems management agent'
feedback body 'AWS SSM agent is already installed by default in the AMI'
pkgmgr install 'ansible'

# Install security apps
feedback h1 'Install security apps to protect the host'
pkgmgr install 'fail2ban'
app_rkhunter
app_tripwire
app_lsm
app_lsa
app_osquery

pam_google_mfa

# General tools
feedback h1 'Useful tools for Linux'
feedback h2 'AWS EC2 tools'
pkgmgr install 'ec2-ami-tools'
feedback h2 'Whole host use/performance'
pkgmgr install 'stacer sysstat nmon strace'
feedback h2 'CPU use/performance'
feedback h2 'Memory use/performance'
feedback h2 'Disk use/performance'
pkgmgr install 'iotop'
feedback h2 'Network configuration'
pkgmgr install 'ethtool'
feedback h2 'Network use/performance'
pkgmgr install 'iptraf-ng nethogs iftop bmon iperf3'
app_ookla_speedtest_client
feedback h2 'Database client'
app_mariadb_client

mount_efs_volume
# Import the common constants and variables held in a script on the EFS volume. This saves duplicating code between scripts
feedback h2 'Import the common variables from EFS'
source "${efs_mount_point}/script/common_variables.sh"

# Create users and groups for the vhosts on EFS
# The OS and base AMI packages use 0-1000 for the UID's and GID's they require. I have reserved 1001-2000 for UID's and GID's that are intrinsic to the build. UID & GID 2001 and above are for general use.
feedback h1 'Configure local users and groups to match those on EFS'
# Groups
feedback h3 'Create groups'
groupadd --gid 2001 vhost_all
groupadd --gid 2002 vhost_owners
groupadd --gid 2003 vhost_users
# Users
feedback h3 'Create users'
for vhost_dir in ${vhost_dir_list}
do
  if [ "${vhost_dir}" == "_default_" ] || [ "${vhost_dir}" == "example.com" ]
  then
    # These vhost directories don't need vhost users created
    feedback body "Skipping ${vhost_dir}"
  else
    # Create the owner accounts
    # Owner accounts exist to own the data & processes for the vhost, and (using their group) can delegate full access within a vhost to an end user
    vhost_dir_uid=$(stat -c '%u' "${vhost_root}/${vhost_dir}")
    vhost_dir_gid=$(stat -c '%g' "${vhost_root}/${vhost_dir}")
    feedback body "Creating owner ${vhost_dir} with UID/GID ${vhost_dir_uid}/${vhost_dir_gid} for ${vhost_root}/${vhost_dir}"
    groupadd --gid ${vhost_dir_gid} "${vhost_dir}"
    useradd --uid ${vhost_dir_uid} --gid ${vhost_dir_gid} --shell '/sbin/nologin' --home-dir "${vhost_root}/${vhost_dir}" --no-create-home --groups vhost_owners,vhost_all -c 'Web space owner' "${vhost_dir}"
  fi
done

configure_awscli

mount_s3_bucket

app_apache2

# Install Ghost Script, a PostScript interpreter and renderer that is used by WordPress for PDFs
pkgmgr install 'ghostscript'

app_mariadb_server

# Install scripting languages
feedback h1 'Install scripting languages'
pkgmgr install 'python3'
pkgmgr install 'golang'
pkgmgr install 'ruby'
pkgmgr install 'nodejs npm'
app_php

# Assign the EIP for web2 to this instance, this will remove the EIP from any running instance
associate_eip

# Create the DNS records for this instance
create_dns_record

# Create a certificate for this instance, and configure its PKI duties like certificate renewals
create_pki_certificate

app_ookla_speedtest_server

# Disable services we don't need
disable_service iscsi.service
disable_service iscsid.service
disable_service open-iscsi.service

# Grab warnings and errors to review
grep -i 'error' '/var/log/cloud-init-output.log' | sort | uniq >> ~/for_review.log
grep -i 'warn' '/var/log/cloud-init-output.log' | sort | uniq >> ~/for_review.log

# Thats all I wrote
feedback title "Build script finished - https://${instance_id}.${hosting_domain}/wiki/"
### add a reboot to enable apparmor?
exit 0
