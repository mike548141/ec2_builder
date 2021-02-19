# ec2_builder
Scripts to build EC2 instances

# ACM
Swap from Let's Encrypt to AWS ACM for public certs. Removes the external dependency
Keep the Lets Encrypt code for future use

# SES
Setup AWS SES for email from the web server.
Could also use this for things like the printer, the NAS etc...

Server Name:    
email-smtp.us-east-1.amazonaws.com
Port:    25, 465 or 587
Use Transport Layer Security (TLS):    Yes
Authentication:    Your SMTP credentials. See below for more information.
ses-smtp-user.20210215-013032
SMTP Username:
AKIA54JEHKOIT77VIJEZ
SMTP Password:
BOxvx0SXBldW0Ff4JQ3I5aR55uOaDQl1M2FkldQYyTwX

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


* Other tests and recommendations from https://observatory.mozilla.org/analyze/web2.cakeit.nz
incl SSH tests

i.e. general hardening.

