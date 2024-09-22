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
