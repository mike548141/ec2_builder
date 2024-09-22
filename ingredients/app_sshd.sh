#!/usr/bin/env bash
#
# Author:       Mike Clements, Competitive Edge
# Version:      0.1.0 2024-09-22T22:15
# File:         app_sshd.sh
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
		MaxAuthTries 8
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
