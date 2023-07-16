#! /bin/bash
# moving labels from most recent run to back-up folder

if [ "${USER}" != "mapper" ]; then
    echo "$0 must be run as user sandbox"
fi

echo "Copying labels"
#! /bin/bash

echo "Do you want to move into backup the most recent run's labels?"
select yn in "No" "Yes"; do
    case $yn in
        No ) exit;;
        Yes ) break;;
    esac
done

read -s -p "Enter postgis password: " postgis_pw
echo

# Script directory.
SDIR=`dirname $0`

if [[ $SDIR != . ]]; then
    echo "Script must be run from ${USER}/pgsql/ directory"
    exit 1
fi

RUNNO=`PGPASSWORD=$postgis_pw psql -AXt -d Africa -U postgis -c \
"select max(run) from iteration_metrics;"`
if ! [[ $RUNNO =~ ^[0-9]+$ ]] ; then
   echo "error: Not a valid run number" >&2; exit 1
fi

NAMES=`PGPASSWORD=$postgis_pw psql -AXt -d Africa -U postgis -c \
"select name from incoming_names where run = $RUNNO;"`

# Date and path for backup
# extract bucket
for item in ${config_array[*]}
do
    if [[ $item == *"bucket"* ]]; then
        bucket=`echo "$item" | cut -d'"' -f 2`
    fi
done

hostname=`hostname -s`
S3Path=s3://$bucket/$hostname/RUN_$RUNNO/

for item in ${NAMES[*]}
do
    # echo "Moving" $item
    aws s3 mv s3://$bucket/labels/ $S3Path --recursive --exclude "*" \
    --include "$item*"
done
 

