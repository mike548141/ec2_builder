#!/usr/bin/env bash

# Check if the script has already been run to save CPU cycles
if [[ ${common_variables} == 1 ]]
then
  echo 'The common variables have already been set, skipping'
else
  echo 'Collecting the variable values'
  #======================================
  # Static variables
  #--------------------------------------
  
  
  #======================================
  # Instance metadata
  #--------------------------------------
  # Get the instance name
  instance_id=`ec2-metadata --instance-id | cut -c 14-`

  # Set the initial AWS region setting using the instances placement so that we can connect to the AWS SSM parameter store
  aws_region=`ec2-metadata --availability-zone | cut -c 12-20`
  
  # Collect the instances tags
  tenancy=`aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'tenancy'].Value" --output text --region ${aws_region}`
  resource_environment=`aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'resource_environment'].Value" --output text --region ${aws_region}`
  service_group=`aws ec2 describe-tags --query "Tags[?ResourceType == 'instance' && ResourceId == '${instance_id}' && Key == 'service_group'].Value" --output text --region ${aws_region}`
  
    
  #======================================
  # Variables set from the parameter store
  #--------------------------------------
  # Define the parameter store structure
  app='ec2_builder-web_server.sh'
  common_parameters="/${tenancy}/${resource_environment}/common"
  app_parameters="/${tenancy}/${resource_environment}/${service_group}/${app}"
  
  # The AWS region to use
  aws_region=`aws ssm get-parameter --name "${app_parameters}/awscli/aws_region" --query 'Parameter.Value' --output text --region ${aws_region}`

  # The domain name used by the servers for web hosting, this domain name represents the hosting provider and not its customers vhosts
  hosting_domain=`aws ssm get-parameter --name "${app_parameters}/hosting_domain" --query 'Parameter.Value' --output text --region ${aws_region}`

  # The AWS EFS mount point used to hold virtual host config, content and logs that is shared between web hosts (aka instances)
  efs_mount_point=`aws ssm get-parameter --name "${app_parameters}/efs_mount_point" --query 'Parameter.Value' --output text --region ${aws_region}`

  # The AWS S3 mount point used to hold web content that is shared between web hosts, not currently used but is cheaper than EFS
  s3_mount_point=`aws ssm get-parameter --name "${app_parameters}/s3_mount_point" --query 'Parameter.Value' --output text --region ${aws_region}`

  # The root directory that all the vhosts folders are within
  vhost_root=`aws ssm get-parameter --name "${app_parameters}/vhost_root" --query 'Parameter.Value' --output text --region ${aws_region}`

  # The web servers config file that includes each of the individual vhosts
  vhost_httpd_conf=`aws ssm get-parameter --name "${app_parameters}/vhost_httpd_conf" --query 'Parameter.Value' --output text --region ${aws_region}`
  
  
  #======================================
  # Dynamic variables set by querying the instance for data
  #--------------------------------------
  # Get the instances public IPv4 address
  public_ipv4=`ec2-metadata --public-ipv4 | cut -c 14-`
  
  # A list of the vhosts that the web server loads e.g. cakeit.nz
  vhost_list=`grep -i '^Include ' ${vhost_httpd_conf} | sed "s|[iI]nclude \"${vhost_root}/||g; s|/conf/httpd.conf\"||g;"`

  # A list of the vhost folders stored, irrespective of if they are loaded by the web server or not
  vhost_dir_list=`ls --directory ${vhost_root}/*/ | sed "s|^${vhost_root}/||;s|/$||;"`

  #======================================
  # Finish up
  #--------------------------------------
  # Add a flag variable to show the script has already been run to save re-running it multiple times
  common_variables=1

  echo 'Common variables have been set'
fi
