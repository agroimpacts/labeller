#! /bin/bash

# Child scripts are in the same directory
SDIR=`dirname $0`

# Assumes we were called with '/home/${USER}/labeller/pgsql/<script_name>'.
IFS='/'
array=($0)
USER=${array[2]}
IFS=' '

HOSTNAME=`hostname -s`
# user check
if [ "${USER}" == "mapper" ]; then
    DB="Africa"
elif [ "${USER}" == "sandbox" ]; then
    DB="AfricaSandbox"
else
    echo "$0 must be run as user /home/mapper or /home/sandbox"
    exit 1
fi

# Set up some path variables
# get s3 bucket name from config
for item in ${config_array[*]}
do
    if [[ $item == *"bucket"* ]]; then
        bucket=`echo "$item" | cut -d'"' -f 2`
    fi
done
DATE="$(date +%Y-%m-%d)"
S3Path=s3://$bucket/backups/database/$HOSTNAME/$DATE
WAYPath=$SDIR/s3backups

# Backup the DB.
PGNAME="${DB}"_daily.pgdump
echo "About to backup $DB database to $PGNAME. This could take some time..."
PGPASSWORD=$postgis_pw pg_dump -Fc -f $WAYPath/$PGNAME -U postgis $DB
if [[ $? != 0 ]]; then
     exit 1
fi

# Move it into S3 bucket
echo "copying" $WAYPath/$PGNAME $S3Path/$PGNAME
su -c "export PATH=$PATH:/home/$USER/.local/bin; \
aws s3 cp $WAYPath/$PGNAME $S3Path/$PGNAME" $USER
# aws s3 cp $WAYPath/$PGNAME $S3Path/$PGNAME
if [[ $? != 0 ]]; then
     exit 1
fi

# Remove back-up file from instance
echo "Cleaning up: deleting" $WAYPath/$PGNAME
rm -f $WAYPath/$PGNAME
if [[ $? != 0 ]]; then
    exit 1
fi       
echo ""
