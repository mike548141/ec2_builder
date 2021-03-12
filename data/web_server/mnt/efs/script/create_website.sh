efs_mount_point='/mnt/efs'
source "${efs_mount_point}/script/common_variables.sh"
source "${efs_mount_point}/script/update_instance-vhosts_pki.sh"

certbot certonly --domains "${instance_id}.${hosting_domain},web2.${hosting_domain}" --apache --non-interactive --agree-tos --email "${pki_email}" --no-eff-email --logs-dir '/var/log/letsencrypt' --redirect --must-staple --staple-ocsp --hsts --uir


certbot certonly --domains "cakeit.nz,www.cakeit.nz" --apache --non-interactive --agree-tos --email "help@cakeit.nz" --no-eff-email --logs-dir "/mnt/efs/vhost/cakeit.nz/log/letsencrypt" --redirect --must-staple --staple-ocsp --hsts --uir

certbot certonly --domains "i-0efcff734f69df9a5.cakeit.nz,web2.cakeit.nz" --apache --non-interactive --agree-tos --email "help@cakeit.nz" --no-eff-email --logs-dir '/var/log/letsencrypt' --redirect --must-staple --staple-ocsp --hsts --uir
