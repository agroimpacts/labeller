#! /bin/bash

if [ "$USER" != "root" ]; then
    echo "Error: You must run $0 as root."
    exit 1
fi
CERTHOSTNAME=$1
if [ -z "$CERTHOSTNAME" ]; then
    echo "`date`: Usage: $0 <cert_hostname> <old_certname>"
    exit 1
fi

OLDCERTNAME=$2
if [ -z "$OLDCERTNAME" ]; then
    echo "`date`: Usage: $0 <cert_hostname> <old_certname>"
    exit 1
fi

echo "NOTE: You must have added the necessary primary DNS entry for this server."
echo "Based on the specified cert hostname, the following DNS entry is required,"
echo "and a cert for that entry will be created:"
echo "          $CERTHOSTNAME"
read -rsp $'Press any key to continue...\n' -n 1

webroot_dir1="/home/mapper/labeller"
echo "NOTE: You must have made the following directory be world-readable in Apache "
echo "      for the default HTTP virtual host (in httpd.conf):"
echo "          $webroot_dir1/.well-known"
read -rsp $'Press any key to continue...\n' -n 1

# Use the commented out command below to debug using the letsencrypt test server.
#certbot certonly --server https://acme-staging-v02.api.letsencrypt.org/directory --webroot -w $webroot_dir1 -d $CERTHOSTNAME

# change the hostname
hostnamectl set-hostname $CERTHOSTNAME

# Remove old certname if specified as second argument
if [ -n "$OLDCERTNAME" ]; then
    echo "Deleting $OLDCERTNAME"
    rm -f /etc/letsencrypt/livecerts
    certbot delete --cert-name $OLDCERTNAME  # change this to argument or delete-all
fi 

# create new cert for new hostname
certbot certonly --webroot -w $webroot_dir1 -d $CERTHOSTNAME
# Create softlink for apache's generic cert path.
ln -s /etc/letsencrypt/live/$CERTHOSTNAME /etc/letsencrypt/livecerts

echo "NOTE: The SSLCertificateFile and SSLCertificateKeyFile directives in the Apache "
echo "      ssl.conf file should now be set for each virtual host to the appropriate path "
echo "      above for fullchain.pem and privkey.pem respectively."
echo "NOTE: To renew, use a root crontab job to run 'certbot renew' every week "
echo "      (followed by an apache restart)."
