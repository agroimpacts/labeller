#! /bin/bash
# for backing up data captured in production tables ahead of clearing db for 
# new run

# Script directory check
SDIR=`dirname $0`
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

# Read in table names
# Enter table names into array
declare -a tablearray
if [ ! -f tables_to_backup.txt ]; then
    echo "'tables_to_backup.txt' file not found! You need to have this file" \
    "if you want to back up individual tables. Create it and put one table" \
    "name per line."
    exit 1
fi
let i=0
while IFS=$'\n' read -r line_data; do
    tablearray[i]="${line_data}"
    ((++i))
done < tables_to_backup.txt

echo "Do you want to backup these tables?"
for item in ${tablearray[*]}
do
    echo $item
done

select yn in "No" "Yes"; do
    case $yn in
        No ) exit;;
        Yes ) break;;
    esac
done

# inputs for destination. Default is to backup to a sub-folder named for the
# instance-id, unless otherwise specified
HOSTNAME=`hostname -s`
# IID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
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

# RUNNO=`PGPASSWORD=$postgis_pw psql -AXt -d Africa -U postgis -c \
# "select max(run) from iteration_metrics;"`
# if ! [[ $RUNNO =~ ^[0-9]+$ ]] ; then
#    echo "error: Not a valid run number" >&2; exit 1
# fi

# Date and path for backup
# hostname=`hostname -s`
DATE="$(date +%Y-%m-%d)"
# HOUR="$(date +%H.%M)"
S3Path=s3://activemapper/backups/database/$HOSTNAME/$DATE
# S3Path=s3://activemapper/backups/database/$hostname/RUN_$RUNNO/$DATE
WAYPath=$SDIR/s3backups
# pgname="${hostname}_$dbname"

if [[ ! -d "$WAYPath" ]]; then
    echo "Creating" $WAYPath
    mkdir $WAYPath
fi

for item in ${tablearray[*]}
do
    echo "Backing up" $item
    OFILE=$WAYPath/$item.sql
    echo $OFILE
    PGPASSWORD=$postgis_pw pg_dump -U postgis -a -t $item Africa > $OFILE
    if [[ $? != 0 ]]; then
        exit 1
    fi

    echo "Copying" $item "to S3"
    aws s3 cp $OFILE $S3Path/$item.sql
    echo $S3Path/$item.sql
    if [[ $? != 0 ]]; then
        exit 1
    fi

    echo "Cleaning up"
    rm -f $OFILE
    if [[ $? != 0 ]]; then
        exit 1
    fi
done
