#! /bin/bash
# Script to create complete back up of database.

# Script directory.
SDIR=`dirname $0`

# directory check
 if [[ $SDIR != . ]]; then
     echo "Script must be run from ${USER}/pgsql/ directory"
     exit 1
fi

# user check
if [ "${USER}" == "mapper" ]; then
    DB="Africa"
elif [ "${USER}" == "sandbox" ]; then
    DB="AfricaSandbox"
else
    echo "$0 must be run as user mapper or user sandbox"
    # DB="Africa"
    exit 1
fi

# Read instance id - unless specified manually, backups will be done under the 
# instance-id
#IID=INSTANCE-ID
#IID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
HOSTNAME=`hostname -s`

# inputs
if [[ -z "$1" ]]; then
    read -p 'Do you want to backup to a named folder (yes or no): ' answer
    if [ $answer == "yes" ]; then
        read -p 'Provide s3 folder name (under s3:/../backups): ' s3folder
        HOSTNAME=$s3folder
        echo "Backing up to $HOSTNAME"
    fi
    if [ $answer == "no" ]; then
        echo "Backing up to $HOSTNAME"
    fi
    read -s -p "Enter postgis password: " postgis_pw
    echo
else
    postgis_pw=$1
fi

# Set up some path variables
# Get S3Path from config
source "$PROJDIR/pgsql/parse_yaml.sh"
config_array=$(parse_yaml $PROJDIR/common/config.yaml)

# extract bucket
for item in ${config_array[*]}
do
    if [[ $item == *"bucket"* ]]; then
        bucket=`echo "$item" | cut -d'"' -f 2`
    fi
done

DATE="$(date +%Y-%m-%d)"
S3Path=s3://$bucket/$HOSTNAME/$DATE
WAYPath=$SDIR/s3backups

# Backup the DB.
echo "About to backup $DB database to $DB.pgdump. This could take some time..."
PGPASSWORD=$postgis_pw pg_dump -Fc -f $WAYPath/$DB.pgdump -U postgis $DB
if [[ $? != 0 ]]; then
     exit 1
fi

# Move it into S3 bucket
echo "copying" $WAYPath/$DB.pgdump $S3Path/$DB.pgdump
aws s3 cp $WAYPath/$DB.pgdump $S3Path/$DB.pgdump
if [[ $? != 0 ]]; then
     exit 1
fi

# Remove back-up file from instance
echo "Cleaning up: deleting" $WAYPath/$DB.pgdump
rm -f $WAYPath/$DB.pgdump
if [[ $? != 0 ]]; then
    exit 1
fi                                            
