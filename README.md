# ec2_builder
Scripts to build EC2 instances

# Definitions
## Playbook
Describes a series of manual steps to achieve an outcome, for example the steps to access AWS and build a web server using a recipe.
## Recipe
A script that configures a host for its role e.g. web server.
## Module
Modules are code snippets that are re-usable across multiple recipes. Examples are a chunk of code that hardens the OpenSSH daemon, or code to format sreen or log output from a script.

# IAM
Review and reduce permissions for EC2 IAM profile

# SES
Setup AWS SES for email from the web server.. Could also use this for things like the printer, the NAS etc...
Server Name:    email-smtp.us-east-1.amazonaws.com
Port:    25, 465 or 587
Use Transport Layer Security (TLS):    Yes
Authentication:    Your SMTP credentials. Keepass URI: {REF:T@I:629FB137-197C-4C33-9F1B-6E0FCF6339A8}

# fpm-php service
13/2/2021
I found that I was getting a Service Unavailable error message (503) when I tried to browse to https://web2.cakeit.nz/wiki/
At first I thought MediaWiki could not talk to the database. But I eventually found that php-fpm was not running, it appears to be disabled in the config.
I ran the following to get it working again but this might be something 
```
# systemctl restart php-fpm.service
```

# Other
* pki script on efs to update (launched from build script) to update the list of vhosts on each instance
* Sync cake it.nz and default http conf
* CSP header for default
* Other tests and recommendations from https://observatory.mozilla.org/analyze/web2.cakeit.nz incl SSH tests i.e. general hardening.
