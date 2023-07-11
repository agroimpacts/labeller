#! /bin/bash

# Enter table names into array

if [ "${USER}" == "mapper" ]; then
    DB="Africa"
elif [ "${USER}" == "sandbox" ]; then
    DB="AfricaSandbox"
else
    echo "$0 must be run as user mapper or user sandbox"
    # DB="Africa"
    exit 1
fi

# Read in table
# Enter table names into array
declare -a tablearray

# Load file into array.
if [ ! -f tables_to_restore.txt ]; then
    echo "'tables_to_restore.txt' file not found! You need to have this file" \
    "if you want to restore individual tables. Create it and put one table" \
    "name per line."
    exit 1
fi

let i=0
while IFS=$'\n' read -r line_data; do
    tablearray[i]="${line_data}"
    ((++i))
done < tables_to_restore.txt

echo "Do you want to restore these tables from backup on S3 into $DB?"
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


echo "In what sub-folder of s3://..backups/database/ are the tables?"
read -p 'Enter sub-folder name (typically the instance ID): ' s3folder
echo "From what date was the back-up?"
read -p "Enter date as YYYY-MM-DD (e.g. 2018-11-14): " ymd
read -s -p "Enter postgis password: " postgis_pw
echo

echo "$0 restoring tables from s3://..backups/database/$s3folder into $DB"

# Script directory.
SDIR=`dirname $0`

# Date and path for backup
# DATE=$year-$month-$day
S3Path=s3://activemapper/backups/database/$s3folder/$ymd

# Fetch the table from S3
echo $S3Path
for item in ${tablearray[*]}
do
    echo "Fetching" $item "from S3"
    IFILE=$SDIR/migration/$item.sql
    # S3FILE=$S3Path/$item.sql
    S3FILE=$S3PATH/$item.sql  # get file name
    if [ -z "$S3FILE" ]; then
        echo $dump "doesn't exist in" $S3PATH
        exit 1
    fi
    aws s3 cp $S3FILE $IFILE
    if [[ $? != 0 ]]; then
        exit 1
    fi

    # Deleting from table
    PGPASSWORD=$postgis_pw psql -U postgis $DB -c "delete from $item;"
    if [[ $? != 0 ]]; then
        exit 1
    fi

    # Replacing with new table
    PGPASSWORD=$postgis_pw psql -U postgis $DB < $IFILE
    if [[ $? != 0 ]]; then
        exit 1
    fi

    echo "Cleaning up"
    rm -f $IFILE
    if [[ $? != 0 ]]; then
        exit 1
    fi
done
